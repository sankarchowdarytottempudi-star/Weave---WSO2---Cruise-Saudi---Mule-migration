"""Catalogues of the Phase 1 design (plan v2.1: Appendix A, Appendix B, sections 7.1, 8.4, 8.5, 14.4).

Every value here is part of the frozen contract; the database enforces the same sets with CHECK
constraints (see migrations/versions/0001_initial.py)."""
from __future__ import annotations

from enum import Enum


class StrEnum(str, Enum):
    def __str__(self) -> str:  # pragma: no cover - cosmetic
        return self.value


class IdentityStatus(StrEnum):
    """Appendix A: status of a Guest's identity processing (CRM Guest 'Identity Status')."""
    PENDING_IDENTITY = "PENDING_IDENTITY"
    IDENTITY_REUSED_CERTAIN = "IDENTITY_REUSED_CERTAIN"
    NEW_IDENTITY_CREATED = "NEW_IDENTITY_CREATED"
    NEW_IDENTITY_PENDING_REVIEW = "NEW_IDENTITY_PENDING_REVIEW"
    MULTIPLE_IDENTITY_CONFLICT = "MULTIPLE_IDENTITY_CONFLICT"
    PAIR_REPAIR_REQUIRED = "PAIR_REPAIR_REQUIRED"
    REVIEW_DECISION_PREPARED = "REVIEW_DECISION_PREPARED"
    REVIEW_DATA_CHANGED = "REVIEW_DATA_CHANGED"
    CONFIRMED_SAME_PERSON = "CONFIRMED_SAME_PERSON"
    CONFIRMED_DIFFERENT_PERSON = "CONFIRMED_DIFFERENT_PERSON"
    HOUSEHOLD_RELATIONSHIP = "HOUSEHOLD_RELATIONSHIP"
    EXCLUDED_NON_DIRECT = "EXCLUDED_NON_DIRECT"
    IDENTITY_PROCESSING_FAILED = "IDENTITY_PROCESSING_FAILED"


class Decision(StrEnum):
    """Production outcome of one evaluation (section 11.3 'decision')."""
    REUSE_EXISTING_IDENTITY = "REUSE_EXISTING_IDENTITY"
    CREATE_NEW_IDENTITY = "CREATE_NEW_IDENTITY"
    CREATE_PROVISIONAL_IDENTITY = "CREATE_PROVISIONAL_IDENTITY"
    KEEP_EXISTING_IDENTITY = "KEEP_EXISTING_IDENTITY"   # re-evaluation: IDs never change automatically (D04)
    EXCLUDED_NON_DIRECT = "EXCLUDED_NON_DIRECT"


class DecisionType(StrEnum):
    """Section 7.1 'Identity Decision Type' (CERTAIN split by the contact that qualified, as in 11.3)."""
    CERTAIN_PHONE = "CERTAIN_PHONE"
    CERTAIN_EMAIL = "CERTAIN_EMAIL"
    FOUR_FIELD = "FOUR_FIELD"
    NEW = "NEW"
    MULTIPLE_IDENTITY = "MULTIPLE_IDENTITY"
    PAIR_REPAIR = "PAIR_REPAIR"
    MANUAL = "MANUAL"
    GUARDRAIL = "GUARDRAIL"            # extension: candidate guardrail exceeded (section 8.3 / 14.5)
    NONE = "NONE"                      # excluded or unchanged


class ProcessingState(StrEnum):
    """Section 8.4."""
    RECEIVED = "RECEIVED"
    DECIDED_PENDING_CRM = "DECIDED_PENDING_CRM"
    COMMITTED = "COMMITTED"
    CRM_UPDATE_FAILED = "CRM_UPDATE_FAILED"
    REJECTED_STALE = "REJECTED_STALE"
    FAILED = "FAILED"


class ReviewState(StrEnum):
    """Section 8.5."""
    REVIEW_OPEN = "REVIEW_OPEN"
    REVIEW_DECISION_PREPARED = "REVIEW_DECISION_PREPARED"
    REVIEW_DATA_CHANGED = "REVIEW_DATA_CHANGED"
    REVIEW_CRM_UPDATE_PENDING = "REVIEW_CRM_UPDATE_PENDING"
    REVIEW_COMMITTED = "REVIEW_COMMITTED"
    REVIEW_FAILED = "REVIEW_FAILED"


class ReviewerAction(StrEnum):
    """Section 14.4."""
    CONFIRM_SAME_PERSON = "CONFIRM_SAME_PERSON"
    CONFIRM_DIFFERENT_PEOPLE = "CONFIRM_DIFFERENT_PEOPLE"
    CONFIRM_HOUSEHOLD = "CONFIRM_HOUSEHOLD"
    DEFER = "DEFER"
    REVERSE_DECISION = "REVERSE_DECISION"


class ReviewKind(StrEnum):
    """Section 15.2 queue categories."""
    MULTIPLE_IDENTITY_CONFLICT = "MULTIPLE_IDENTITY_CONFLICT"
    FOUR_FIELD_REVIEW = "FOUR_FIELD_REVIEW"
    PAIR_REPAIR = "PAIR_REPAIR"
    REEVALUATION_CONFLICT = "REEVALUATION_CONFLICT"
    GUARDRAIL = "GUARDRAIL"


class IdentityLifecycle(StrEnum):
    """Section 7.2 'Identity Status' of a Guest Identity, plus RESERVED before the CRM commit."""
    RESERVED = "RESERVED"
    ACTIVE = "ACTIVE"
    PROVISIONAL = "PROVISIONAL"
    RETIRED = "RETIRED"
    ALIAS = "ALIAS"
    BLOCKED = "BLOCKED"


class PairIntegrity(StrEnum):
    COMPLETE = "COMPLETE"
    INCOMPLETE = "INCOMPLETE"
    CONFLICT = "CONFLICT"


class PhoneConfidence(StrEnum):
    HIGH_E164 = "HIGH_E164"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    INVALID = "INVALID"
    MISSING = "MISSING"


class FieldResult(StrEnum):
    EXACT = "EXACT"
    CONFLICT = "CONFLICT"
    MISSING = "MISSING"
    SUPPRESSED = "SUPPRESSED"
    LOW_CONFIDENCE = "LOW_CONFIDENCE"


class ShadowLabel(StrEnum):
    SHADOW_AUTO_CANDIDATE = "SHADOW_AUTO_CANDIDATE"
    SHADOW_REVIEW_CANDIDATE = "SHADOW_REVIEW_CANDIDATE"
    SHADOW_SEPARATE = "SHADOW_SEPARATE"


IDENTITY_FIELDS = ("firstName", "lastName", "dateOfBirth", "phone", "email")
