"""Reconciliation support (sections 14.5, 17): queries the Integration Service's reconciliation job
uses to find decisions whose CRM write or commit may have been lost. Read-only; no CRM access."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.engine import Connection

from app.db.models import identity_decision as d
from app.domain.enums import ProcessingState


def stale_pending(conn: Connection, older_than: timedelta = timedelta(minutes=15), limit: int = 500) -> list[dict]:
    """Decisions still waiting for CRM (pending or retryable failure) older than the cut-off; the
    reconciliation job compares each with CRM and calls commit (CRM has it) or retries the write."""
    cutoff = datetime.now(timezone.utc) - older_than
    rows = conn.execute(select(d.c.decision_id, d.c.crm_guest_record_id, d.c.state, d.c.created_time)
                        .where(d.c.state.in_([ProcessingState.DECIDED_PENDING_CRM.value,
                                              ProcessingState.CRM_UPDATE_FAILED.value]),
                               d.c.created_time < cutoff)
                        .order_by(d.c.created_time).limit(limit)).mappings().all()
    return [{"decisionId": r["decision_id"], "crmGuestRecordId": r["crm_guest_record_id"], "state": r["state"],
             "createdTime": r["created_time"].isoformat()} for r in rows]


def counts_by_state(conn: Connection) -> dict:
    from sqlalchemy import func
    return {s: n for s, n in conn.execute(select(d.c.state, func.count()).group_by(d.c.state)).all()}
