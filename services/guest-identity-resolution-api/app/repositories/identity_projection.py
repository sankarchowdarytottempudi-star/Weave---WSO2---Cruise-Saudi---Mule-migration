"""Identity projection: encrypted Global/Loyalty pair, integrity and lifecycle (8.1)."""
from __future__ import annotations

import uuid
from typing import Optional

from sqlalchemy import select, update
from sqlalchemy.engine import Connection

from app.db.crypto import Crypto
from app.services.pair_allocator import is_reusable_pair
from app.db.models import identity_projection as ip
from app.domain.enums import IdentityLifecycle, PairIntegrity
from app.repositories.guest_projection import now


def get(conn: Connection, identity_id: str, for_update: bool = False):
    q = select(ip).where(ip.c.identity_id == identity_id)
    if for_update:
        q = q.with_for_update()
    return conn.execute(q).mappings().first()


def by_crm_id(conn: Connection, crm_identity_record_id: str):
    return conn.execute(select(ip).where(ip.c.crm_identity_record_id == crm_identity_record_id)).mappings().first()


def by_reservation(conn: Connection, decision_id: str):
    return conn.execute(select(ip).where(ip.c.reserved_by_decision_id == decision_id)).mappings().first()


def create_reserved(conn: Connection, crypto: Crypto, decision_id: str, global_id: str, loyalty_id: str,
                    process: str, rule_version: str) -> str:
    identity_id = str(uuid.uuid4())
    t = now()
    conn.execute(ip.insert().values(
        identity_id=identity_id, global_id_enc=crypto.encrypt(global_id), loyalty_id_enc=crypto.encrypt(loyalty_id),
        global_id_hash=crypto.keyed_hash(global_id), loyalty_id_hash=crypto.keyed_hash(loyalty_id),
        pair_integrity=PairIntegrity.COMPLETE.value, lifecycle_status=IdentityLifecycle.RESERVED.value,
        committed=False, created_by_process=process, rule_version=rule_version,
        reserved_by_decision_id=decision_id, created_time=t, modified_time=t))
    return identity_id


def ensure_external(conn: Connection, crypto: Crypto, crm_identity_record_id: str, global_id: Optional[str],
                    loyalty_id: Optional[str], rule_version: str) -> str:
    """An identity known to CRM but not yet indexed (baseline gap): index it as committed. A pair
    with only one ID is INCOMPLETE and therefore never reusable (section 16.2)."""
    found = by_crm_id(conn, crm_identity_record_id)
    if found:
        # Global-to-Loyalty must stay one-to-one (16.1): another Guest carrying a different ID for
        # the same identity makes the pair CONFLICT, i.e. never reusable.
        for col, value in (("global_id_hash", global_id), ("loyalty_id_hash", loyalty_id)):
            h = crypto.keyed_hash(value)
            if h and found[col] and h != found[col] and found["pair_integrity"] != PairIntegrity.CONFLICT.value:
                conn.execute(update(ip).where(ip.c.identity_id == found["identity_id"])
                             .values(pair_integrity=PairIntegrity.CONFLICT.value, modified_time=now()))
        return found["identity_id"]
    identity_id = str(uuid.uuid4())
    t = now()
    # Mule eligibility rule: both IDs present and no legacy '-' Global ID, else never reusable
    integrity = PairIntegrity.COMPLETE if is_reusable_pair(global_id, loyalty_id) else PairIntegrity.INCOMPLETE
    g_hash, l_hash = crypto.keyed_hash(global_id), crypto.keyed_hash(loyalty_id)
    for col, h in ((ip.c.global_id_hash, g_hash), (ip.c.loyalty_id_hash, l_hash)):
        other = conn.execute(select(ip.c.identity_id).where(col == h)).first() if h else None
        if other:
            # same ID already on another identity (e.g. one Loyalty ID under several Global IDs):
            # BOTH become CONFLICT and neither is ever reused automatically
            conn.execute(update(ip).where(ip.c.identity_id == other[0])
                         .values(pair_integrity=PairIntegrity.CONFLICT.value, modified_time=now()))
            integrity, g_hash, l_hash = PairIntegrity.CONFLICT, None, None
    conn.execute(ip.insert().values(
        identity_id=identity_id, crm_identity_record_id=crm_identity_record_id,
        global_id_enc=crypto.encrypt(global_id), loyalty_id_enc=crypto.encrypt(loyalty_id),
        global_id_hash=g_hash, loyalty_id_hash=l_hash, pair_integrity=integrity.value,
        lifecycle_status=IdentityLifecycle.ACTIVE.value, committed=True, created_by_process="BASELINE",
        rule_version=rule_version, created_time=t, modified_time=t))
    return identity_id


def commit(conn: Connection, identity_id: str, crm_identity_record_id: Optional[str], lifecycle: IdentityLifecycle) -> None:
    values = dict(committed=True, lifecycle_status=lifecycle.value, modified_time=now())
    if crm_identity_record_id:
        values["crm_identity_record_id"] = crm_identity_record_id
    conn.execute(update(ip).where(ip.c.identity_id == identity_id).values(**values))


def set_lifecycle(conn: Connection, identity_id: str, lifecycle: IdentityLifecycle,
                  surviving_identity_id: Optional[str] = None) -> None:
    conn.execute(update(ip).where(ip.c.identity_id == identity_id).values(
        lifecycle_status=lifecycle.value, surviving_identity_id=surviving_identity_id, modified_time=now()))


def pair(crypto: Crypto, row) -> tuple[Optional[str], Optional[str]]:
    if row is None:
        return None, None
    return crypto.decrypt(row["global_id_enc"]), crypto.decrypt(row["loyalty_id_enc"])
