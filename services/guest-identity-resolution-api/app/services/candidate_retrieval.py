"""Candidate retrieval (9.1): bounded exact indexed blocks, identity-level dedup, guardrail."""
from __future__ import annotations

from typing import Optional

from sqlalchemy.engine import Connection

from app.repositories import guest_projection
from app.services.normalization import NormalizedIdentity
from app.services.rule_engine import Candidate


def retrieve(conn: Connection, norm: NormalizedIdentity, guest_id: str, exclude_identity: Optional[str],
             guardrail: int) -> tuple[list[Candidate], bool]:
    return guest_projection.candidates(conn, norm, guest_id, exclude_identity, guardrail)
