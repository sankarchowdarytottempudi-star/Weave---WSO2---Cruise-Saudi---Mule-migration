"""Review API used by the Integration Review API (9.2, 9.6, 9.7). PostgreSQL only - no CRM."""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.deps import Container, Reviewer, container, require_service, reviewer_claims
from app.domain.errors import forbidden, invalid
from app.schemas.review import DecisionPreparationRequest, FreshnessFailedRequest, ReviewCommitRequest, ReviewFailRequest

router = APIRouter(dependencies=[Depends(require_service)], tags=["review"])


@router.get("/v1/review-cases/{case_id}")
def get_case(case_id: str, who: Reviewer = Depends(reviewer_claims), c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.review.get_case(conn, case_id, set(who.roles))


@router.post("/v1/review-cases/{case_id}/decision-preparations")
def prepare(case_id: str, body: DecisionPreparationRequest, who: Reviewer = Depends(reviewer_claims),
            c: Container = Depends(container)):
    if body.caseId != case_id:
        raise invalid("caseId in the body must match the path.")
    if body.reviewerId != who.reviewer_id:
        raise forbidden("reviewerId must be the authenticated reviewer.")
    with c.engine.begin() as conn:
        return c.review.prepare(conn, body, set(who.roles))


@router.post("/v1/review-decisions/{rd_id}/freshness-failed")
def freshness_failed(rd_id: str, body: FreshnessFailedRequest, c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.review.freshness_failed(conn, rd_id, body)


@router.post("/v1/review-decisions/{rd_id}/commit")
def commit(rd_id: str, body: ReviewCommitRequest, c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.review.commit(conn, rd_id)


@router.post("/v1/review-decisions/{rd_id}/fail")
def fail(rd_id: str, body: ReviewFailRequest, c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.review.fail(conn, rd_id, body.retryable, body.errorCode)
