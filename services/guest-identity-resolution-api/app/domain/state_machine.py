"""Allowed state transitions (8.4, 8.5) - one place, enforced by the services; the database CHECK
constraints enforce the state sets themselves."""
from __future__ import annotations

from app.domain.enums import ProcessingState as P, ReviewState as R
from app.domain.errors import invalid_state

PROCESSING = {
    P.RECEIVED: {P.DECIDED_PENDING_CRM, P.COMMITTED, P.REJECTED_STALE, P.FAILED},
    P.DECIDED_PENDING_CRM: {P.COMMITTED, P.CRM_UPDATE_FAILED, P.FAILED},
    P.CRM_UPDATE_FAILED: {P.COMMITTED, P.CRM_UPDATE_FAILED, P.FAILED},
    P.COMMITTED: set(), P.REJECTED_STALE: set(), P.FAILED: set(),
}
REVIEW = {
    R.REVIEW_OPEN: {R.REVIEW_DECISION_PREPARED},
    R.REVIEW_DATA_CHANGED: {R.REVIEW_DECISION_PREPARED},
    R.REVIEW_DECISION_PREPARED: {R.REVIEW_COMMITTED, R.REVIEW_DATA_CHANGED, R.REVIEW_CRM_UPDATE_PENDING, R.REVIEW_OPEN},
    R.REVIEW_CRM_UPDATE_PENDING: {R.REVIEW_COMMITTED, R.REVIEW_DATA_CHANGED, R.REVIEW_OPEN,
                                  R.REVIEW_CRM_UPDATE_PENDING},
    R.REVIEW_COMMITTED: set(), R.REVIEW_FAILED: set(),
}


def check_processing(current: str, target: P) -> None:
    if target not in PROCESSING[P(current)]:
        raise invalid_state(f"A decision in state {current} cannot move to {target.value}.")


def check_review(current: str, target: R) -> None:
    if target not in REVIEW[R(current)]:
        raise invalid_state(f"A review case in state {current} cannot move to {target.value}.")
