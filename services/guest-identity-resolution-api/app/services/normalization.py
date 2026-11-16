"""Deterministic normalization of the five identity fields (plan section 12.2).

Pure functions: no I/O, no clock except an injectable 'today' for future-date checks. Each field
yields its normalized value, validity, confidence/placeholder flags and whether it may count as
evidence. Normalization happens only inside Python (section 11.4)."""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Optional

import phonenumbers

from app.config import Settings
from app.domain.enums import PhoneConfidence

_WS = re.compile(r"\s+")
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_DOB_FORMATS = ("%Y-%m-%d", "%d/%m/%Y", "%Y/%m/%d", "%d-%m-%Y", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M:%SZ")


@dataclass(frozen=True)
class NameValue:
    original: Optional[str]
    canonical: Optional[str]          # None when missing/invalid/placeholder
    placeholder: bool = False


@dataclass(frozen=True)
class DobValue:
    original: Optional[str]
    key: Optional[date]               # None when missing/invalid/placeholder
    placeholder: bool = False
    suspicious: bool = False          # e.g. 1970-01-01: a placeholder only when over-shared
    day: Optional[int] = None
    month: Optional[int] = None
    year: Optional[int] = None


@dataclass(frozen=True)
class PhoneValue:
    original: Optional[str]
    e164: Optional[str]
    tail: Optional[str]
    confidence: PhoneConfidence = PhoneConfidence.MISSING

    @property
    def high(self) -> bool:
        return self.confidence is PhoneConfidence.HIGH_E164 and self.e164 is not None


@dataclass(frozen=True)
class EmailValue:
    original: Optional[str]
    key: Optional[str]
    placeholder: bool = False


@dataclass(frozen=True)
class NormalizedIdentity:
    first: NameValue
    last: NameValue
    dob: DobValue
    phone: PhoneValue
    email: EmailValue
    notes: tuple[str, ...] = field(default_factory=tuple)
    alt_phone: PhoneValue = field(default_factory=lambda: PhoneValue(None, None, None))

    def high_phones(self) -> set:
        """Both phone fields (Mobile and Phone) count as phone evidence when HIGH_E164."""
        return {p.e164 for p in (self.phone, self.alt_phone) if p.high}


def _blank(value: Optional[str]) -> bool:
    return value is None or not str(value).strip()


def normalize_name(value: Optional[str], settings: Settings) -> NameValue:
    if _blank(value):
        return NameValue(original=value, canonical=None)
    text = unicodedata.normalize("NFKC", str(value)).casefold()
    for ch in settings.approved_name_punctuation:
        text = text.replace(ch, " " if ch in "-_/" else "")
    text = _WS.sub(" ", text).strip()
    if not text or not any(c.isalpha() for c in text):
        return NameValue(original=value, canonical=None)
    if text in settings.name_placeholders:
        return NameValue(original=value, canonical=None, placeholder=True)
    return NameValue(original=value, canonical=text)


def normalize_dob(value: Optional[str], settings: Settings, today: Optional[date] = None) -> DobValue:
    if _blank(value):
        return DobValue(original=value, key=None)
    raw = str(value).strip()
    parsed: Optional[date] = None
    for fmt in _DOB_FORMATS:
        try:
            parsed = datetime.strptime(raw, fmt).date()
            break
        except ValueError:
            continue
    if parsed is None:
        return DobValue(original=value, key=None)
    today = today or date.today()
    parts = dict(day=parsed.day, month=parsed.month, year=parsed.year)
    if parsed.isoformat() in settings.dob_placeholders:
        return DobValue(original=value, key=None, placeholder=True, **parts)
    age = today.year - parsed.year - ((today.month, today.day) < (parsed.month, parsed.day))
    if parsed > today or age > settings.dob_max_age_years:
        return DobValue(original=value, key=None, **parts)          # invalid: future or older than the limit
    return DobValue(original=value, key=parsed, suspicious=parsed.isoformat() in settings.dob_suspicious, **parts)


def normalize_phone(value: Optional[str], country: Optional[str], settings: Settings,
                    citizenship: Optional[str] = None) -> PhoneValue:
    """E.164 with explicit context only (ASSUMPTION, owner 2026-11-16): a country code in the number
    ('+' or '00') wins; otherwise the Guest's country, then citizenship, from the snapshot; otherwise
    LOW - never HIGH_E164 and never a forced +966. A configured fallback region gives MEDIUM only."""
    if _blank(value):
        return PhoneValue(original=value, e164=None, tail=None)
    raw = str(value).strip()
    digits = re.sub(r"\D", "", raw)
    tail = digits[-9:] if len(digits) >= 9 else None
    if raw.startswith("00"):
        raw = "+" + raw[2:].lstrip()
    region, confidence_if_valid = None, PhoneConfidence.HIGH_E164
    if not raw.startswith("+") and settings.phone_966_without_plus_is_e164 and re.fullmatch(r"966\d{9}", digits):
        raw = "+" + digits                         # baseline: Mobile mostly stored as 966XXXXXXXXX
    if not raw.startswith("+"):
        context = next((c.strip().upper() for c in (country, citizenship) if c and c.strip()), None)
        if context:
            region = context
        elif settings.phone_default_region:
            region, confidence_if_valid = settings.phone_default_region, PhoneConfidence.MEDIUM
        elif settings.phone_saudi_local_without_context == "MEDIUM" and re.fullmatch(r"0?5\d{8}", digits):
            region, confidence_if_valid = "SA", PhoneConfidence.MEDIUM   # Saudi pattern, unconfirmed country
        else:
            return PhoneValue(original=value, e164=None, tail=tail, confidence=PhoneConfidence.LOW)
    try:
        parsed = phonenumbers.parse(raw, region)
    except phonenumbers.NumberParseException:
        return PhoneValue(original=value, e164=None, tail=tail, confidence=PhoneConfidence.INVALID)
    national = str(parsed.national_number)
    tail = national[-9:] if len(national) >= 9 else tail
    if phonenumbers.is_valid_number(parsed):
        return PhoneValue(original=value,
                          e164=phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164),
                          tail=tail, confidence=confidence_if_valid)
    if phonenumbers.is_possible_number(parsed):
        return PhoneValue(original=value, e164=None, tail=tail, confidence=PhoneConfidence.LOW)
    return PhoneValue(original=value, e164=None, tail=tail, confidence=PhoneConfidence.INVALID)


def normalize_email(value: Optional[str], settings: Settings) -> EmailValue:
    if _blank(value):
        return EmailValue(original=value, key=None)
    key = str(value).strip().lower()
    if not _EMAIL.match(key):
        return EmailValue(original=value, key=None)
    if key in settings.email_placeholders or any(re.search(p, key) for p in settings.email_placeholder_patterns):
        return EmailValue(original=value, key=None, placeholder=True)
    return EmailValue(original=value, key=key)


def normalize_identity(first: Optional[str], last: Optional[str], dob: Optional[str], phone: Optional[str],
                       email: Optional[str], country: Optional[str], settings: Settings,
                       today: Optional[date] = None, citizenship: Optional[str] = None,
                       alt_phone: Optional[str] = None) -> NormalizedIdentity:
    return NormalizedIdentity(
        first=normalize_name(first, settings),
        last=normalize_name(last, settings),
        dob=normalize_dob(dob, settings, today),
        phone=normalize_phone(phone, country, settings, citizenship),
        email=normalize_email(email, settings),
        alt_phone=normalize_phone(alt_phone, country, settings, citizenship),
    )
