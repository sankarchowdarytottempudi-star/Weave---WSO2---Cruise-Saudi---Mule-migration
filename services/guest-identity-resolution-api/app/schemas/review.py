"""Review models (plan sections 11.5 - 11.7, 9.6, 9.7)."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.events import GuestIdentityEvent


class VersionShown(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crmGuestRecordId: str
    crmModifiedTime: datetime


class DecisionPreparationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    caseId: str
    reviewerId: str = Field(min_length=1, max_length=100)
    action: str
    selectedIdentityId: Optional[str] = None
    comment: Optional[str] = Field(default=None, max_length=2000)
    versionsShown: list[VersionShown] = Field(min_length=1)
    idempotencyKey: str = Field(min_length=1, max_length=300)
    followUpDate: Optional[date] = None


class FreshnessFailedRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    snapshots: list[GuestIdentityEvent] = Field(min_length=1)
    correlationId: Optional[str] = None


class ReviewCommitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crmModifiedTimes: Optional[list[VersionShown]] = None
    correlationId: Optional[str] = None


class AssignmentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    assigneeId: str = Field(min_length=1, max_length=100)
    assignedBy: str = Field(min_length=1, max_length=100)


class CommentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    authorId: str = Field(min_length=1, max_length=100)
    text: str = Field(min_length=1, max_length=2000)


class ReviewFailRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    retryable: bool
    errorCode: str = Field(min_length=1, max_length=100)
