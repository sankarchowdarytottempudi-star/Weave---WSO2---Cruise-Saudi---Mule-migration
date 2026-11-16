"""Request/response models for evaluation and decisions (plan sections 11.2, 11.3, 11.4)."""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SUPPORTED_SCHEMA_VERSIONS = ("1.0",)


class GuestIdentityEvent(BaseModel):
    """Evaluation / re-evaluation event: the complete identity snapshot (D14)."""
    model_config = ConfigDict(extra="forbid")

    schemaVersion: str
    eventId: str = Field(min_length=1, max_length=100)
    eventType: Literal["GUEST_IDENTITY_EVALUATION_REQUESTED", "GUEST_IDENTITY_REEVALUATION_REQUESTED"]
    idempotencyKey: Optional[str] = Field(default=None, max_length=300)
    correlationId: str = Field(min_length=1, max_length=100)
    sourceSystem: str = Field(min_length=1, max_length=50)
    sourceRecordId: str = Field(min_length=1, max_length=100)
    crmGuestRecordId: str = Field(min_length=1, max_length=100)
    crmModifiedTime: datetime
    firstName: Optional[str] = Field(default=None, max_length=200)
    lastName: Optional[str] = Field(default=None, max_length=200)
    dateOfBirth: Optional[str] = Field(default=None, max_length=40)
    phone: Optional[str] = Field(default=None, max_length=60)
    alternatePhone: Optional[str] = Field(default=None, max_length=60)    # CRM Phone (phone = Mobile)
    email: Optional[str] = Field(default=None, max_length=320)
    countryCode: Optional[str] = Field(default=None, max_length=2)
    citizenshipCode: Optional[str] = Field(default=None, max_length=2)
    sourceCode: Optional[str] = Field(default=None, max_length=50)
    agencyCode: Optional[str] = Field(default=None, max_length=50)
    agencyName: Optional[str] = Field(default=None, max_length=200)   # the direct-scope key
    active: bool = True
    currentGlobalId: Optional[str] = Field(default=None, max_length=50)
    currentLoyaltyId: Optional[str] = Field(default=None, max_length=50)
    currentIdentityId: Optional[str] = Field(default=None, max_length=100)

    @field_validator("schemaVersion")
    @classmethod
    def _version(cls, v: str) -> str:
        if v not in SUPPORTED_SCHEMA_VERSIONS:
            raise ValueError(f"unsupported schemaVersion {v!r}")
        return v

    @field_validator("crmModifiedTime")
    @classmethod
    def _aware(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError("crmModifiedTime must carry a time zone (UTC)")
        return v

    @model_validator(mode="after")
    def _one_identity_field(self):
        if not any((self.firstName, self.lastName, self.dateOfBirth, self.phone, self.alternatePhone, self.email)):
            raise ValueError("at least one identity field must be present")
        return self


class DecisionResponse(BaseModel):
    decisionId: str
    decision: str
    decisionType: str
    identityStatus: str
    crmIdentityRecordId: Optional[str] = None
    identityId: Optional[str] = None
    globalId: Optional[str] = None
    loyaltyId: Optional[str] = None
    provisional: bool = False
    reviewRequired: bool
    reviewCaseId: Optional[str] = None
    reviewPriority: Optional[str] = None
    crmUpdateRequired: bool = True
    ruleVersion: str
    reasonCodes: list[str]
    reasonSummary: str
    processingState: str
    shadow: Optional[dict] = None


class CommitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crmIdentityRecordId: Optional[str] = Field(default=None, max_length=100)
    crmGuestModifiedTime: Optional[datetime] = None
    correlationId: Optional[str] = Field(default=None, max_length=100)


class FailRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    retryable: bool
    errorCode: str = Field(min_length=1, max_length=100)
    correlationId: Optional[str] = Field(default=None, max_length=100)


def scope_agency(ev: "GuestIdentityEvent") -> Optional[str]:
    """The approved scope is by agency NAME; agencyCode is accepted as a fallback carrier only."""
    return ev.agencyName if ev.agencyName else ev.agencyCode
