"""Bootstrap (plan 16) request models: bulk index snapshots, no CRM involvement."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

MAX_BATCH = 5000


class BootstrapRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")
    crmGuestRecordId: str = Field(min_length=1, max_length=100)
    sourceSystem: str = Field(default="CRM_BASELINE", max_length=50)
    sourceRecordId: Optional[str] = Field(default=None, max_length=100)
    crmModifiedTime: datetime
    firstName: Optional[str] = Field(default=None, max_length=200)
    lastName: Optional[str] = Field(default=None, max_length=200)
    dateOfBirth: Optional[str] = Field(default=None, max_length=40)
    phone: Optional[str] = Field(default=None, max_length=60)
    alternatePhone: Optional[str] = Field(default=None, max_length=60)
    email: Optional[str] = Field(default=None, max_length=320)
    countryCode: Optional[str] = Field(default=None, max_length=2)
    citizenshipCode: Optional[str] = Field(default=None, max_length=2)
    sourceCode: Optional[str] = Field(default=None, max_length=50)
    agencyCode: Optional[str] = Field(default=None, max_length=50)
    agencyName: Optional[str] = Field(default=None, max_length=200)
    active: bool = True
    currentIdentityId: Optional[str] = Field(default=None, max_length=100)
    currentGlobalId: Optional[str] = Field(default=None, max_length=50)
    currentLoyaltyId: Optional[str] = Field(default=None, max_length=50)

    @field_validator("crmModifiedTime")
    @classmethod
    def _aware(cls, v: datetime) -> datetime:
        if v.tzinfo is None:
            raise ValueError("crmModifiedTime must carry a time zone (UTC)")
        return v


class BootstrapBatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    batchId: str = Field(min_length=1, max_length=100, pattern=r"^[A-Za-z0-9._:-]+$")
    records: list[BootstrapRecord] = Field(min_length=1, max_length=MAX_BATCH)


class DryRunRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    afterGuestId: Optional[str] = None
    limit: int = Field(default=2000, ge=1, le=MAX_BATCH)
    onlyWithoutIdentity: bool = False
