"""Decision state: GET, commit, fail (9.2)."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.deps import Container, container, require_service
from app.schemas.events import CommitRequest, DecisionResponse, FailRequest

router = APIRouter(prefix="/v1/guest-identities/decisions", dependencies=[Depends(require_service)],
                   tags=["decisions"])


@router.get("/{decision_id}", response_model=DecisionResponse)
def get_decision(decision_id: str, c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.evaluation.response(conn, decision_id)


@router.post("/{decision_id}/commit", response_model=DecisionResponse)
def commit(decision_id: str, body: CommitRequest, c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.evaluation.commit(conn, decision_id, body.crmIdentityRecordId)


@router.post("/{decision_id}/fail", response_model=DecisionResponse)
def fail(decision_id: str, body: FailRequest, c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.evaluation.fail(conn, decision_id, body.retryable, body.errorCode)
