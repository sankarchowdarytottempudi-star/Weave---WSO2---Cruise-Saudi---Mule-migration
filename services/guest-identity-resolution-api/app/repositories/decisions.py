"""Processing requests (idempotency) and decisions (audit + commit handshake)."""
from __future__ import annotations

import uuid
from typing import Optional

from sqlalchemy import select, update
from sqlalchemy.engine import Connection

from app.db.models import identity_decision as d, processing_request as p
from app.repositories.guest_projection import now


def request_by_key(conn: Connection, key: str, for_update: bool = False):
    q = select(p).where(p.c.idempotency_key == key)
    if for_update:
        q = q.with_for_update()
    return conn.execute(q).mappings().first()


def insert_request(conn: Connection, key: str, payload_hash: str, kind: str, guest: str, correlation_id: str,
                   state: str) -> str:
    rid = str(uuid.uuid4())
    t = now()
    conn.execute(p.insert().values(request_id=rid, idempotency_key=key, payload_hash=payload_hash, kind=kind,
                                   crm_guest_record_id=guest, correlation_id=correlation_id, state=state,
                                   attempts=1, created_time=t, updated_time=t))
    return rid


def update_request(conn: Connection, request_id: str, **values) -> None:
    values["updated_time"] = now()
    conn.execute(update(p).where(p.c.request_id == request_id).values(**values))


def bump_attempt(conn: Connection, request_id: str) -> None:
    conn.execute(update(p).where(p.c.request_id == request_id).values(attempts=p.c.attempts + 1, updated_time=now()))


def new_decision_id() -> str:
    return "IDDEC-" + uuid.uuid4().hex[:20].upper()


def insert_decision(conn: Connection, **values) -> None:
    t = now()
    conn.execute(d.insert().values(created_time=t, updated_time=t, **values))


def get_decision(conn: Connection, decision_id: str, for_update: bool = False):
    q = select(d).where(d.c.decision_id == decision_id)
    if for_update:
        q = q.with_for_update()
    return conn.execute(q).mappings().first()


def update_decision(conn: Connection, decision_id: str, **values) -> None:
    values["updated_time"] = now()
    conn.execute(update(d).where(d.c.decision_id == decision_id).values(**values))


def pending(conn: Connection, limit: int = 500):
    return conn.execute(select(d.c.decision_id, d.c.crm_guest_record_id, d.c.state)
                        .where(d.c.state.in_(("DECIDED_PENDING_CRM", "CRM_UPDATE_FAILED")))
                        .order_by(d.c.created_time).limit(limit)).mappings().all()
