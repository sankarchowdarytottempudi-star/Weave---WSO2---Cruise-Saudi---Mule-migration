"""POST /v1/guest-identities/evaluate and /re-evaluate (9.2)."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.deps import Container, container, require_service
from app.domain.errors import invalid, stale_event
from app.schemas.events import DecisionResponse, GuestIdentityEvent
from app.services.evaluation_service import STALE

router = APIRouter(prefix="/v1/guest-identities", dependencies=[Depends(require_service)], tags=["evaluation"])


def _run(c: Container, ev: GuestIdentityEvent, kind: str) -> dict:
    with c.engine.begin() as conn:
        result = c.evaluation.evaluate(conn, ev, kind)
    if result is STALE:
        raise stale_event()                     # raised after the REJECTED_STALE record is committed
    return result


@router.post("/evaluate", response_model=DecisionResponse)
def evaluate(ev: GuestIdentityEvent, c: Container = Depends(container)):
    if ev.eventType != "GUEST_IDENTITY_EVALUATION_REQUESTED":
        raise invalid("eventType must be GUEST_IDENTITY_EVALUATION_REQUESTED for /evaluate.")
    return _run(c, ev, "EVALUATE")


@router.post("/re-evaluate", response_model=DecisionResponse)
def re_evaluate(ev: GuestIdentityEvent, c: Container = Depends(container)):
    if ev.eventType != "GUEST_IDENTITY_REEVALUATION_REQUESTED":
        raise invalid("eventType must be GUEST_IDENTITY_REEVALUATION_REQUESTED for /re-evaluate.")
    return _run(c, ev, "REEVALUATE")
