import os
from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.config import database_url, get_settings
from app.schemas.events import GuestIdentityEvent, scope_agency
from app.schemas.review import DecisionPreparationRequest

BASE = dict(schemaVersion="1.0", eventId="E1", eventType="GUEST_IDENTITY_EVALUATION_REQUESTED", correlationId="C1",
            sourceSystem="SEAWARE", sourceRecordId="1", crmGuestRecordId="R1",
            crmModifiedTime="2026-11-16T10:20:30Z", firstName="Test")


def test_valid_event():
    ev = GuestIdentityEvent(**BASE)
    assert ev.crmModifiedTime.tzinfo is not None and ev.active


@pytest.mark.parametrize("change", [{"schemaVersion": "2.0"}, {"crmModifiedTime": "2026-11-16T10:20:30"},
                                    {"firstName": None}, {"unknownField": 1}, {"crmGuestRecordId": ""},
                                    {"eventType": "OTHER"}, {"countryCode": "SAU"}])
def test_invalid_event(change):
    with pytest.raises(ValidationError):
        GuestIdentityEvent(**{**BASE, **change})


def test_scope_agency_prefers_name():
    assert scope_agency(GuestIdentityEvent(**BASE, agencyCode="AROYA", agencyName="RIYADH SEASON")) == "RIYADH SEASON"
    assert scope_agency(GuestIdentityEvent(**BASE, agencyCode="AROYA")) == "AROYA"


def test_preparation_requires_versions():
    with pytest.raises(ValidationError):
        DecisionPreparationRequest(caseId="RC-1", reviewerId="u", action="DEFER", versionsShown=[], idempotencyKey="k")


def test_settings_from_environment(monkeypatch, tmp_path):
    secret = tmp_path / "pw"
    secret.write_text("s3cret\n")
    for k, v in {"GIR_DB_HOST": "db.internal", "GIR_DB_NAME": "gir", "GIR_DB_USER": "gir_app",
                 "GIR_DB_PASSWORD_FILE": str(secret), "GIR_DB_SSLROOTCERT": "/ca.crt",
                 "GIR_DIRECT_SOURCE_CODES": "MOBAPP, WHATSAPP", "GIR_CERTAIN_REUSE_ENABLED": "false",
                 "GIR_SHADOW_ONLY_ENABLED": "yes"}.items():
        monkeypatch.setenv(k, v)
    monkeypatch.delenv("GIR_DATABASE_URL", raising=False)
    get_settings.cache_clear()
    try:
        s = get_settings()
        assert s.db_password == "s3cret" and s.direct_source_codes == ("MOBAPP", "WHATSAPP")
        assert not s.certain_reuse_enabled and s.shadow_only_enabled and not s.weighted_auto_enabled
        url = database_url(s)
        assert url.host == "db.internal" and url.query["sslmode"] == "verify-full" and url.query["sslrootcert"] == "/ca.crt"
        assert "s3cret" not in repr(url) and "s3cret" not in repr(s)
    finally:
        get_settings.cache_clear()


def test_database_url_requires_configuration(monkeypatch):
    import dataclasses
    from app.config import Settings
    with pytest.raises(RuntimeError):
        database_url(Settings())
    assert database_url(dataclasses.replace(Settings(), database_url="postgresql+psycopg://u@h/d")).host == "h"
