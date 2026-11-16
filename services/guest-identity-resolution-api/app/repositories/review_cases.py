"""Review case projection, candidates and prepared manual decisions (8.1, 8.5, 9.6, 9.7)."""
from __future__ import annotations

import uuid

from sqlalchemy import case as sql_case, delete, func, select, update
from sqlalchemy.engine import Connection

from app.db.models import (review_candidate as rc, review_case_event as rce, review_case_projection as rcp,
                           review_comment as rcm, review_decision as rd)
from app.repositories.guest_projection import now


def new_case_id() -> str:
    return "RC-" + uuid.uuid4().hex[:16].upper()


def new_review_decision_id() -> str:
    return "RD-" + uuid.uuid4().hex[:16].upper()


def create(conn: Connection, case_id: str, guest: str, provisional_identity_id, decision_id: str, kind: str,
           priority: str, rule_version: str, reasons: list, sla_due_time=None) -> None:
    t = now()
    conn.execute(rcp.insert().values(case_id=case_id, crm_guest_record_id=guest,
                                     provisional_identity_id=provisional_identity_id, source_decision_id=decision_id,
                                     kind=kind, priority=priority, state="REVIEW_OPEN", rule_version=rule_version,
                                     reason_codes=reasons, created_time=t, updated_time=t, sla_due_time=sla_due_time))
    add_event(conn, case_id, "CREATED", None, {"kind": kind, "priority": priority, "reasonCodes": reasons})


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


def add_event(conn: Connection, case_id: str, event_type: str, actor_id, details: dict) -> None:
    """History entries carry codes, states and user ids only - never personal details (they reach
    audit users unmasked)."""
    conn.execute(rce.insert().values(case_id=case_id, event_type=event_type, actor_id=actor_id, details=details,
                                     created_time=now()))


def history(conn: Connection, case_id: str):
    return conn.execute(select(rce).where(rce.c.case_id == case_id).order_by(rce.c.event_id)).mappings().all()


def add_comment(conn: Connection, comment_id: str, case_id: str, author_id: str, text_enc: bytes) -> None:
    conn.execute(rcm.insert().values(comment_id=comment_id, case_id=case_id, author_id=author_id, text_enc=text_enc,
                                     created_time=now()))


def comments(conn: Connection, case_id: str):
    return conn.execute(select(rcm).where(rcm.c.case_id == case_id).order_by(rcm.c.created_time)).mappings().all()


def queue(conn: Connection, kind=None, status=None, assignee=None, limit: int = 50, offset: int = 0):
    q = select(rcp, select(func.count()).where(rc.c.case_id == rcp.c.case_id).scalar_subquery().label("candidate_count"))
    if kind:
        q = q.where(rcp.c.kind.in_(kind))
    if status:
        q = q.where(rcp.c.state.in_(status))
    else:
        q = q.where(rcp.c.state != "REVIEW_COMMITTED")
    if assignee == "unassigned":
        q = q.where(rcp.c.assigned_to.is_(None))
    elif assignee:
        q = q.where(rcp.c.assigned_to == assignee)
    total = conn.execute(select(func.count()).select_from(q.subquery())).scalar_one()
    order = (sql_case((rcp.c.priority == "HIGH", 0), else_=1), func.coalesce(rcp.c.sla_due_time, rcp.c.created_time),
             rcp.c.created_time, rcp.c.case_id)
    rows = conn.execute(q.order_by(*order).limit(limit).offset(offset)).mappings().all()
    return rows, total
