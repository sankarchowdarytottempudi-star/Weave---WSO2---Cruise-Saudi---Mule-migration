"""Dependency injection and service authentication (sections 9.5 step 1, 15.1, 18)."""
from __future__ import annotations

import hmac
from dataclasses import dataclass
from typing import Optional

from fastapi import Header, Request
from sqlalchemy.engine import Engine

from app.config import Settings
from app.db.crypto import Crypto
from app.domain.errors import ApiError, unauthorized
from app.services.bootstrap_service import BootstrapService
from app.services.evaluation_service import EvaluationService
from app.services.pair_allocator import PairAllocator, build_allocator
from app.services.review_service import ReviewService


@dataclass
class Container:
    settings: Settings
    engine: Engine
    crypto: Crypto
    evaluation: EvaluationService
    review: ReviewService
    bootstrap: BootstrapService

    @classmethod
    def build(cls, settings: Settings, engine: Engine, allocator: Optional[PairAllocator] = None) -> "Container":
        crypto = Crypto(settings.data_key_b64, settings.data_key_id, settings.hmac_key_b64)
        return cls(settings, engine, crypto,
                   EvaluationService(settings, crypto, allocator or build_allocator(settings, crypto)),
                   ReviewService(settings, crypto), BootstrapService(settings, crypto))


def container(request: Request) -> Container:
    return request.app.state.container


def require_service(request: Request, authorization: Optional[str] = Header(default=None)) -> None:
    """Bearer service credential issued to the Integration Service; constant-time comparison;
    fails closed when no credential is configured."""
    expected = request.app.state.container.settings.service_token
    if not expected or not authorization or not authorization.startswith("Bearer "):
        raise unauthorized()
    if not hmac.compare_digest(authorization[7:].encode(), expected.encode()):
        raise unauthorized()


def require_docs(request: Request, authorization: Optional[str] = Header(default=None)) -> None:
    """The interactive docs accept the Bearer credential, or HTTP Basic with the credential as the
    password (so a browser can open them); otherwise 401 with a Basic challenge."""
    import base64
    expected = request.app.state.container.settings.service_token
    supplied = ""
    if authorization and authorization.startswith("Bearer "):
        supplied = authorization[7:]
    elif authorization and authorization.startswith("Basic "):
        try:
            supplied = base64.b64decode(authorization[6:]).decode().split(":", 1)[1]
        except Exception:
            supplied = ""
    if not expected or not supplied or not hmac.compare_digest(supplied.encode(), expected.encode()):
        raise ApiError("UNAUTHORIZED", 401, "Authentication is required.", _headers={"WWW-Authenticate": 'Basic realm="gir"'})


@dataclass(frozen=True)
class Reviewer:
    reviewer_id: str
    roles: frozenset
    correlation_id: str


def reviewer_claims(x_reviewer_id: Optional[str] = Header(default=None),
                    x_reviewer_roles: Optional[str] = Header(default=None),
                    x_correlation_id: Optional[str] = Header(default=None)) -> Reviewer:
    """Reviewer claims are asserted by the Integration Service after it authenticated the CRM user
    (15.1); Python trusts them only on a request that already passed require_service."""
    if not x_reviewer_id or not x_correlation_id:
        raise ApiError("INVALID_REQUEST", 422, "X-Reviewer-Id and X-Correlation-Id are required.")
    roles = frozenset(r.strip().upper() for r in (x_reviewer_roles or "").split(",") if r.strip())
    return Reviewer(x_reviewer_id, roles, x_correlation_id)
