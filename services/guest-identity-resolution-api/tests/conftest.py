"""Shared fixtures. Synthetic data only; keys are generated per run and never written anywhere."""
from __future__ import annotations

import base64
import dataclasses
import os
from datetime import date

import pytest

from app.config import Settings
from app.services.normalization import normalize_identity

TODAY = date(2026, 11, 16)
SERVICE_TOKEN = base64.urlsafe_b64encode(os.urandom(24)).decode()


def make_settings(**over) -> Settings:
    base = Settings(data_key_b64=base64.b64encode(os.urandom(32)).decode(),
                    hmac_key_b64=base64.b64encode(os.urandom(32)).decode(), service_token=SERVICE_TOKEN)
    return dataclasses.replace(base, **over)


@pytest.fixture
def settings() -> Settings:
    return make_settings()


def norm(settings, first="Muhammad", last="Ali", dob="1985-05-10", phone="+966 55 123 4567",
         email="muhammad.ali@gir-synthetic.invalid", country=None):
    return normalize_identity(first, last, dob, phone, email, country, settings, today=TODAY)
