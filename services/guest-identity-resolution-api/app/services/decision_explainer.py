"""Human summary of a decision (CRM 'Identity Reason Summary'). Contains no personal values."""
from __future__ import annotations

from app.services.rule_engine import RuleResult

_TEXT = {
    "REUSE_EXISTING_IDENTITY": "Exact names, real date of birth and a personal contact matched one existing identity; its pair was reused.",
    "CREATE_NEW_IDENTITY": "No existing identity met the deterministic rule; a new permanent pair was created.",
    "CREATE_PROVISIONAL_IDENTITY": "A provisional pair was created and a review case opened.",
    "KEEP_EXISTING_IDENTITY": "The Guest keeps its existing pair; identity data was re-indexed.",
    "EXCLUDED_NON_DIRECT": "The Guest is outside the direct scope; no identity action.",
}


def summary(result: RuleResult) -> str:
    base = _TEXT.get(result.decision.value, result.decision.value)
    codes = ", ".join(str(r) for r in result.reasons)
    return f"{base} Reasons: {codes}." if codes else base
