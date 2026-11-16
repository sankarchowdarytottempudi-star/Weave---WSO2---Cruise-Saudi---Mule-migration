"""Guest match index: protected display values + normalized keys + CRM Modified Time (8.2)."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.engine import Connection

from app.db.crypto import Crypto
from app.db.models import guest_match_index as g, identity_projection as ip
from app.domain.enums import IdentityLifecycle, PairIntegrity
from app.services.normalization import NormalizedIdentity
from app.services.rule_engine import Candidate


def now() -> datetime:
    return datetime.now(timezone.utc)


def get(conn: Connection, crm_guest_record_id: str, for_update: bool = False):
    q = select(g).where(g.c.crm_guest_record_id == crm_guest_record_id)
    if for_update:
        q = q.with_for_update()
    return conn.execute(q).mappings().first()


def row_values(crypto: Crypto, ev, norm: NormalizedIdentity, direct: bool,
               identity_id: Optional[str] = None, crm_identity_record_id: Optional[str] = None) -> dict:
    values = dict(
        crm_guest_record_id=ev.crmGuestRecordId, source_system=ev.sourceSystem, source_record_id=ev.sourceRecordId,
        source_first_name_enc=crypto.encrypt(ev.firstName), source_last_name_enc=crypto.encrypt(ev.lastName),
        source_dob_enc=crypto.encrypt(ev.dateOfBirth), source_phone_enc=crypto.encrypt(ev.phone),
        source_email_enc=crypto.encrypt(ev.email),
        canonical_first_name=norm.first.canonical, canonical_last_name=norm.last.canonical,
        dob_key=norm.dob.key, dob_is_placeholder=norm.dob.placeholder,
        phone_e164_key=norm.phone.e164 if norm.phone.high else None, phone_tail_key=norm.phone.tail,
        phone_confidence=norm.phone.confidence.value, email_key=norm.email.key,
        source_alt_phone_enc=crypto.encrypt(getattr(ev, "alternatePhone", None)),
        alt_phone_e164_key=norm.alt_phone.e164 if norm.alt_phone.high else None,
        alt_phone_tail_key=norm.alt_phone.tail, alt_phone_confidence=norm.alt_phone.confidence.value,
        active_flag=ev.active, direct_scope_flag=direct, crm_modified_time=ev.crmModifiedTime, indexed_time=now(),
    )
    if identity_id is not None:
        values["identity_id"] = identity_id
        values["crm_identity_record_id"] = crm_identity_record_id
    return values


def upsert(conn: Connection, crypto: Crypto, ev, norm: NormalizedIdentity, direct: bool,
           identity_id: Optional[str] = None, crm_identity_record_id: Optional[str] = None) -> None:
    values = row_values(crypto, ev, norm, direct, identity_id, crm_identity_record_id)
    stmt = insert(g).values(**values)
    updates = {k: stmt.excluded[k] for k in values if k != "crm_guest_record_id"}
    conn.execute(stmt.on_conflict_do_update(index_elements=[g.c.crm_guest_record_id], set_=updates))


def upsert_many(conn: Connection, rows: list[dict]) -> None:
    """One multi-row upsert. Rows without an identity keep the identity already stored."""
    if not rows:
        return
    full = [dict(r, identity_id=r.get("identity_id"), crm_identity_record_id=r.get("crm_identity_record_id")) for r in rows]
    stmt = insert(g).values(full)
    updates = {k: stmt.excluded[k] for k in full[0] if k not in ("crm_guest_record_id", "identity_id", "crm_identity_record_id")}
    updates["identity_id"] = func.coalesce(stmt.excluded.identity_id, g.c.identity_id)
    updates["crm_identity_record_id"] = func.coalesce(stmt.excluded.crm_identity_record_id, g.c.crm_identity_record_id)
    conn.execute(stmt.on_conflict_do_update(index_elements=[g.c.crm_guest_record_id], set_=updates))


def set_identity(conn: Connection, crm_guest_record_id: str, identity_id: Optional[str],
                 crm_identity_record_id: Optional[str] = None) -> None:
    conn.execute(update(g).where(g.c.crm_guest_record_id == crm_guest_record_id)
                 .values(identity_id=identity_id, crm_identity_record_id=crm_identity_record_id))


def candidates(conn: Connection, norm: NormalizedIdentity, exclude_guest: str, exclude_identity: Optional[str],
               limit: int) -> tuple[list[Candidate], bool]:
    """Exact indexed blocks only (8.3). Every CERTAIN and every four-field agreement contains the
    phone, the email, or first+last+DOB, so these blocks are complete; the tail key only discovers
    shadow candidates. Returns (candidates, guardrail_exceeded) with dedup at identity level."""
    blocks = []
    if norm.first.canonical and norm.last.canonical and norm.dob.key:
        blocks.append(and_(g.c.canonical_first_name == norm.first.canonical,
                           g.c.canonical_last_name == norm.last.canonical, g.c.dob_key == norm.dob.key))
    for ph in sorted(norm.high_phones()):
        blocks += [g.c.phone_e164_key == ph, g.c.alt_phone_e164_key == ph]
    if norm.email.key:
        blocks.append(g.c.email_key == norm.email.key)
    for tail in sorted({p.tail for p in (norm.phone, norm.alt_phone) if p.tail}):
        blocks += [g.c.phone_tail_key == tail, g.c.alt_phone_tail_key == tail]
    if not blocks:
        return [], False
    q = (select(g.c.crm_guest_record_id, g.c.identity_id, g.c.canonical_first_name, g.c.canonical_last_name,
                g.c.dob_key, g.c.phone_e164_key, g.c.phone_tail_key, g.c.email_key, g.c.crm_identity_record_id,
                g.c.alt_phone_e164_key, g.c.alt_phone_tail_key,
                ip.c.pair_integrity, ip.c.lifecycle_status, ip.c.committed, ip.c.crm_identity_record_id.label("ip_crm"))
         .select_from(g.outerjoin(ip, ip.c.identity_id == g.c.identity_id))
         .where(g.c.active_flag.is_(True), g.c.direct_scope_flag.is_(True),
                g.c.crm_guest_record_id != exclude_guest, or_(*blocks))
         .order_by(g.c.crm_guest_record_id)
         .limit(limit * 5 + 1))
    rows = conn.execute(q).mappings().all()
    out, identities = [], set()
    for r in rows:
        if exclude_identity and r["identity_id"] == exclude_identity:
            continue
        identities.add(r["identity_id"] or f"guest:{r['crm_guest_record_id']}")
        integrity = PairIntegrity(r["pair_integrity"]) if r["pair_integrity"] else None
        reusable = bool(r["identity_id"] and r["committed"] and integrity is PairIntegrity.COMPLETE
                        and r["lifecycle_status"] == IdentityLifecycle.ACTIVE.value)
        out.append(Candidate(crm_guest_record_id=r["crm_guest_record_id"], identity_id=r["identity_id"],
                             first=r["canonical_first_name"], last=r["canonical_last_name"], dob=r["dob_key"],
                             phone_e164=r["phone_e164_key"], phone_tail=r["phone_tail_key"], email=r["email_key"],
                             pair_integrity=integrity, reusable=reusable,
                             crm_identity_record_id=r["ip_crm"] or r["crm_identity_record_id"],
                             alt_phone_e164=r["alt_phone_e164_key"], alt_phone_tail=r["alt_phone_tail_key"]))
    exceeded = len(identities) > limit or len(rows) > limit * 5
    return out, exceeded


def display(crypto: Crypto, row) -> dict:
    return {"firstName": crypto.decrypt(row["source_first_name_enc"]),
            "lastName": crypto.decrypt(row["source_last_name_enc"]),
            "dob": crypto.decrypt(row["source_dob_enc"]),
            "phone": crypto.decrypt(row["source_phone_enc"]),
            "alternatePhone": crypto.decrypt(row["source_alt_phone_enc"]),
            "email": crypto.decrypt(row["source_email_enc"])}


def normalized_from_row(row) -> NormalizedIdentity:
    """Rebuild the matching keys from the projection (used when a review case is re-evaluated)."""
    from app.domain.enums import PhoneConfidence
    from app.services.normalization import DobValue, EmailValue, NameValue, PhoneValue
    return NormalizedIdentity(
        first=NameValue(None, row["canonical_first_name"]), last=NameValue(None, row["canonical_last_name"]),
        dob=DobValue(None, row["dob_key"], placeholder=row["dob_is_placeholder"]),
        phone=PhoneValue(None, row["phone_e164_key"], row["phone_tail_key"],
                         PhoneConfidence(row["phone_confidence"]) if row["phone_confidence"] else PhoneConfidence.MISSING),
        email=EmailValue(None, row["email_key"]),
        alt_phone=PhoneValue(None, row["alt_phone_e164_key"], row["alt_phone_tail_key"],
                             PhoneConfidence(row["alt_phone_confidence"]) if row["alt_phone_confidence"]
                             else PhoneConfidence.MISSING))
