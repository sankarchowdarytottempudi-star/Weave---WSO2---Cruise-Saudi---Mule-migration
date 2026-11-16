"""Table-driven normalization tests (plan 12.2 + owner ASSUMPTIONS of 2026-11-16)."""
from datetime import date

import pytest

from app.domain.enums import PhoneConfidence
from app.services.normalization import normalize_dob, normalize_email, normalize_name, normalize_phone
from tests.conftest import TODAY

NAMES = [
    ("Muhammad", "muhammad"),
    ("  MUHAMMAD  ", "muhammad"),
    ("Mu-hammad", "mu hammad"),
    ("O'Brien", "obrien"),
    ("Abd al_Rahman", "abd al rahman"),
    ("Ａｌｉ", "ali"),                 # NFKC full-width
    ("STRASSE", "strasse"),
    ("Straße", "strasse"),            # casefold
    ("J.R.", "jr"),
    ("محمد", "محمد"),                 # Arabic kept as-is
    ("  ", None),
    (None, None),
    ("123", None),
    ("---", None),
]


@pytest.mark.parametrize("raw,expected", NAMES)
def test_name_canonical(settings, raw, expected):
    assert normalize_name(raw, settings).canonical == expected


@pytest.mark.parametrize("raw", ["TEST", "Unknown", "n/a", "N.A", "xxx", "Guest"])
def test_name_placeholders_are_not_evidence(settings, raw):
    v = normalize_name(raw, settings)
    assert v.canonical is None and v.placeholder


DOBS = [
    ("1985-05-10", date(1985, 5, 10), False, False),
    ("10/05/1985", date(1985, 5, 10), False, False),
    ("1985/05/10", date(1985, 5, 10), False, False),
    ("10-05-1985", date(1985, 5, 10), False, False),
    ("1985-05-10T00:00:00Z", date(1985, 5, 10), False, False),
    ("1900-01-01", None, True, False),
    ("1899-12-31", None, True, False),
    ("0001-01-01", None, True, False),
    ("1800-01-01", None, True, False),
    ("1970-01-01", date(1970, 1, 1), False, True),      # suspicious, not a blanket placeholder
    ("2030-01-01", None, False, False),                 # future -> invalid
    ("1905-01-01", None, False, False),                 # age > 120 -> invalid
    ("1906-11-17", date(1906, 11, 17), False, False),   # age exactly 119 -> valid
    ("31/02/1990", None, False, False),
    ("garbage", None, False, False),
    ("", None, False, False),
    (None, None, False, False),
]


@pytest.mark.parametrize("raw,key,placeholder,suspicious", DOBS)
def test_dob(settings, raw, key, placeholder, suspicious):
    v = normalize_dob(raw, settings, today=TODAY)
    assert (v.key, v.placeholder, v.suspicious) == (key, placeholder, suspicious)


PHONES = [  # value, country, citizenship, e164, confidence
    ("+966 55 123 4567", None, None, "+966551234567", PhoneConfidence.HIGH_E164),
    ("00966551234567", None, None, "+966551234567", PhoneConfidence.HIGH_E164),
    ("+44 20 7946 0958", "SA", None, "+442079460958", PhoneConfidence.HIGH_E164),   # number wins over country
    ("0551234567", "SA", None, "+966551234567", PhoneConfidence.HIGH_E164),         # country context
    ("0551234567", None, "SA", "+966551234567", PhoneConfidence.HIGH_E164),         # citizenship context
    ("202 555 0123", "US", "SA", "+12025550123", PhoneConfidence.HIGH_E164),        # country before citizenship
    ("0551234567", None, None, "+966551234567", PhoneConfidence.MEDIUM),            # Saudi pattern, unconfirmed
    ("551234567", None, None, "+966551234567", PhoneConfidence.MEDIUM),
    ("966551234567", None, None, "+966551234567", PhoneConfidence.HIGH_E164),       # baseline: Mobile w/o '+'
    ("966 55 123 4567", "GB", None, "+966551234567", PhoneConfidence.HIGH_E164),
    ("2025550123", None, None, None, PhoneConfidence.LOW),                          # other digits, no context
    ("+966 12", None, None, None, PhoneConfidence.INVALID),
    ("abc", "SA", None, None, PhoneConfidence.INVALID),
    ("", None, None, None, PhoneConfidence.MISSING),
    (None, "SA", None, None, PhoneConfidence.MISSING),
]


@pytest.mark.parametrize("raw,country,citizen,e164,confidence", PHONES)
def test_phone(settings, raw, country, citizen, e164, confidence):
    v = normalize_phone(raw, country, settings, citizen)
    assert (v.e164, v.confidence) == (e164, confidence)
    assert v.high == (confidence is PhoneConfidence.HIGH_E164)


def test_phone_without_context_is_never_high(settings):
    import dataclasses
    v = normalize_phone("0551234567", None, settings)
    assert not v.high and v.confidence is PhoneConfidence.MEDIUM and v.tail == "551234567"
    low = normalize_phone("0551234567", None, dataclasses.replace(settings, phone_saudi_local_without_context="LOW"))
    assert low.e164 is None and low.confidence is PhoneConfidence.LOW
    off = normalize_phone("966551234567", None, dataclasses.replace(settings, phone_966_without_plus_is_e164=False))
    assert not off.high


def test_phone_fallback_region_gives_medium_only(settings):
    import dataclasses
    s = dataclasses.replace(settings, phone_default_region="SA")
    v = normalize_phone("0551234567", None, s)
    assert v.confidence is PhoneConfidence.MEDIUM and not v.high


EMAILS = [
    ("Muhammad.Ali@Gir-Synthetic.INVALID", "muhammad.ali@gir-synthetic.invalid", False),
    ("  ab@bc.co ", "ab@bc.co", False),
    ("NoEmail@company.sa", None, True),
    ("no-email1@x.com", None, True),
    ("test@gmail.com", None, True),
    ("xxx@yyy.com", None, True),
    ("a@b.com", None, True),
    ("someone@example.com", None, True),
    ("guest@mailinator.com", None, True),
    ("testing.person@gmail.com", "testing.person@gmail.com", False),
    ("noemail@noemail.com", None, True),
    ("TEST@TEST.COM", None, True),
    ("not-an-email", None, False),
    ("a@b", None, False),
    ("", None, False),
    (None, None, False),
]


@pytest.mark.parametrize("raw,key,placeholder", EMAILS)
def test_email(settings, raw, key, placeholder):
    v = normalize_email(raw, settings)
    assert (v.key, v.placeholder) == (key, placeholder)
