"""Review case projection, candidates and prepared manual decisions (8.1, 8.5, 9.6, 9.7)."""
from __future__ import annotations

import uuid

from sqlalchemy import delete, select, update
from sqlalchemy.engine import Connection

from app.db.models import review_candidate as rc, review_case_projection as rcp, review_decision as rd
from app.repositories.guest_projection import now


def new_case_id() -> str:
    return "RC-" + uuid.uuid4().hex[:16].upper()


def new_review_decision_id() -> str:
    return "RD-" + uuid.uuid4().hex[:16].upper()


def create(conn: Connection, case_id: str, guest: str, provisional_identity_id, decision_id: str, kind: str,
           priority: str, rule_version: str, reasons: list) -> None:
    t = now()
    conn.execute(rcp.insert().values(case_id=case_id, crm_guest_record_id=guest,
                                     provisional_identity_id=provisional_identity_id, source_decision_id=decision_id,
                                     kind=kind, priority=priority, state="REVIEW_OPEN", rule_version=rule_version,
                                     reason_codes=reasons, created_time=t, updated_time=t))


def replace_candidates(conn: Connection, case_id: str, rows: list[dict]) -> None:
    conn.execute(delete(rc).where(rc.c.case_id == case_id))
    for rank, row in enumerate(rows, start=1):
        conn.execute(rc.insert().values(case_id=case_id, rank=rank, **row))


def get(conn: Connection, case_id: str, for_update: bool = False):
    q = select(rcp).where(rcp.c.case_id == case_id)
    if for_update:
        q = q.with_for_update()
    return conn.execute(q).mappings().first()


def candidates(conn: Connection, case_id: str):
    return conn.execute(select(rc).where(rc.c.case_id == case_id).order_by(rc.c.rank)).mappings().all()


def update_case(conn: Connection, case_id: str, **values) -> None:
    values["updated_time"] = now()
    conn.execute(update(rcp).where(rcp.c.case_id == case_id).values(**values))


def decision_by_key(conn: Connection, key: str):
    return conn.execute(select(rd).where(rd.c.idempotency_key == key)).mappings().first()


def get_decision(conn: Connection, rd_id: str, for_update: bool = False):
    q = select(rd).where(rd.c.review_decision_id == rd_id)
    if for_update:
        q = q.with_for_update()
    return conn.execute(q).mappings().first()


def insert_decision(conn: Connection, **values) -> None:
    t = now()
    conn.execute(rd.insert().values(created_time=t, updated_time=t, **values))


def update_decision(conn: Connection, rd_id: str, **values) -> None:
    values["updated_time"] = now()
    conn.execute(update(rd).where(rd.c.review_decision_id == rd_id).values(**values))
