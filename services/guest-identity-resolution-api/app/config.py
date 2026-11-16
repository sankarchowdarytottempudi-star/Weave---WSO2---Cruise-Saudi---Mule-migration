"""Runtime configuration (plan sections 20.1 and 24.2).

Every value is configurable by environment. Status of each default (config/config-catalogue.yaml):
  CLIENT-APPROVED - given by the owner (direct scope, ID generation logic, rollout order);
  ASSUMPTION      - industry-practice default, to confirm with the client (PDPL where noted);
  TEST-ONLY       - exists only so tests run; must be provided by the client before UAT. Secrets (database URL, data key, service token) are read from files
mounted by the platform (or env for local tests) and are never logged."""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path


def _secret(name: str, default: str = "") -> str:
    file_path = os.environ.get(f"{name}_FILE")
    if file_path and Path(file_path).is_file():
        return Path(file_path).read_text().strip()
    return os.environ.get(name, default)


def _list(name: str, default: tuple[str, ...]) -> tuple[str, ...]:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return tuple(x.strip() for x in raw.split(",") if x.strip())


def _flag(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    return default if raw is None else raw.strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Settings:
    # ---- feature flags (section 20.1) ----
    certain_reuse_enabled: bool = True
    four_field_review_enabled: bool = True
    weighted_shadow_enabled: bool = True
    weighted_auto_enabled: bool = False          # must stay false in Phase 1 (D11)
    phone_tail_evidence_enabled: bool = False    # must stay false in Phase 1 (D08)
    crm_direct_event_enabled: bool = True
    over_shared_threshold_version: str = "ASSUMPTION-1"
    active_rule_version: str = "1.0"
    # extension (rollout step 1, section 22.2): evaluate and record only - no pair, no link, no case,
    # no CRM update. Off in code; the deployment values turn it on first.
    shadow_only_enabled: bool = False

    # ---- CLIENT-APPROVED direct scope (owner, 2026-11-16): BOTH conditions, exact after trim+casefold ----
    direct_source_codes: tuple[str, ...] = ("INT-ASSC", "INT-CON", "NEWINT-CON", "MOBAPP", "WHATSAPP", "IN HOUSE")
    direct_agency_names: tuple[str, ...] = (
        "AROYA CRUISES MAIN OFFICE", "AROYA CRUISES MAIN OFFICE USD", "AROYA CRUISES MAIN OFFICE EUR",
        "AROYA CRUISES MAIN OFFICE GBP", "FUTURE CRUISES", "RIYADH SEASON", "WHATSAPP")

    # ---- ASSUMPTIONS (industry practice; to confirm with client) ----
    dob_placeholders: tuple[str, ...] = ("1900-01-01", "1899-12-31", "0001-01-01", "1800-01-01")
    dob_suspicious: tuple[str, ...] = ("1970-01-01",)   # placeholder only when over-shared
    dob_suspicious_threshold: int = 3
    dob_max_age_years: int = 120
    name_placeholders: tuple[str, ...] = ("test", "unknown", "na", "n a", "none", "guest", "x", "xx", "xxx")
    email_placeholders: tuple[str, ...] = ("noemail@noemail.com", "test@test.com", "na@na.com", "no@email.com")
    # ASSUMPTION (baseline: ~7% placeholder-looking): regexes on the lower-cased address -> treated as missing
    email_placeholder_patterns: tuple[str, ...] = (
        r"^(no[-_.]?e?mail|noreply|no[-_.]?reply|test|none|na|n/?a|null|nil|unknown|dummy|fake|abc|asd|qwe)\d*@",
        r"^x+@", r"^[a-z]@[a-z]\.", r"@(example|test|invalid|localhost)\.", r"@(mailinator|yopmail|tempmail)\.")
    accept_empty_agency: bool = False        # OWNER DECISION pending (113,677 direct-source guests, empty agency)
    # baseline: Mobile is mostly 966XXXXXXXXX without '+'; local 05/5 numbers without context
    phone_966_without_plus_is_e164: bool = True
    phone_saudi_local_without_context: str = "MEDIUM"   # MEDIUM (never production evidence) | LOW
    phone_default_region: str | None = None      # None = never assume a country (section 12.2)
    over_shared_phone_threshold: int = 5          # > 5 distinct active identities -> suppressed (tune after repair)
    over_shared_email_threshold: int = 5
    # ---- CLIENT-APPROVED ID generation (ported from identity-support-exp-api) ----
    id_allocation_strategy: str = "MULE_COMPAT"   # MULE_COMPAT | SEQUENCE (tests/diagnostics)
    loyalty_id_prefix: str = "12"
    loyalty_id_random_digits: int = 7
    id_allocation_max_attempts: int = 5
    global_id_format: str = "G{n:08d}"            # SEQUENCE strategy only
    loyalty_id_format: str = "L{n:08d}"
    candidate_guardrail: int = 100
    approved_name_punctuation: str = ".,'’`\"-_/"

    # ---- review SLA (ASSUMPTION) and deployment ----
    rate_limit_per_minute: int = 0          # per client address and pod; 0 = off (gateway limits in prod)
    docs_enabled: bool = False               # interactive /docs, always behind the service credential
    sla_conflict_days: int = 1
    sla_four_field_days: int = 2
    work_week: tuple[int, ...] = (6, 0, 1, 2, 3)   # Python weekday numbers: Sun-Thu (KSA); holidays TBD by client
    database_schema: str = "gir"
    # ---- database connection: pure configuration (customer PostgreSQL, provided later) ----
    db_host: str = ""
    db_port: int = 5432
    db_name: str = ""
    db_user: str = ""
    db_sslmode: str = "verify-full"
    db_sslrootcert: str = ""                 # path of the mounted CA bundle
    db_pool_size: int = 5
    db_max_overflow: int = 5
    app_db_role: str = ""                    # migrations grant DML on the schema to this role

    # ---- secrets ----
    db_password: str = field(default="", repr=False)
    database_url: str = field(default="", repr=False)   # full URL override (local tests only)
    data_key_b64: str = field(default="", repr=False)   # 32-byte AES key, base64; key id below
    data_key_id: str = "k1"
    hmac_key_b64: str = field(default="", repr=False)   # for equality/uniqueness hashes of IDs
    service_token: str = field(default="", repr=False)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(
        certain_reuse_enabled=_flag("GIR_CERTAIN_REUSE_ENABLED", True),
        four_field_review_enabled=_flag("GIR_FOUR_FIELD_REVIEW_ENABLED", True),
        weighted_shadow_enabled=_flag("GIR_WEIGHTED_SHADOW_ENABLED", True),
        weighted_auto_enabled=False,
        phone_tail_evidence_enabled=False,
        crm_direct_event_enabled=_flag("GIR_CRM_DIRECT_EVENT_ENABLED", True),
        over_shared_threshold_version=os.environ.get("GIR_OVER_SHARED_THRESHOLD_VERSION", "ASSUMPTION-1"),
        shadow_only_enabled=_flag("GIR_SHADOW_ONLY_ENABLED", False),
        active_rule_version=os.environ.get("GIR_ACTIVE_RULE_VERSION", "1.0"),
        direct_source_codes=_list("GIR_DIRECT_SOURCE_CODES", Settings.direct_source_codes),
        direct_agency_names=_list("GIR_DIRECT_AGENCY_NAMES", Settings.direct_agency_names),
        dob_placeholders=_list("GIR_DOB_PLACEHOLDERS", Settings.dob_placeholders),
        dob_suspicious=_list("GIR_DOB_SUSPICIOUS", Settings.dob_suspicious),
        dob_suspicious_threshold=int(os.environ.get("GIR_DOB_SUSPICIOUS_THRESHOLD", "3")),
        dob_max_age_years=int(os.environ.get("GIR_DOB_MAX_AGE_YEARS", "120")),
        name_placeholders=_list("GIR_NAME_PLACEHOLDERS", Settings.name_placeholders),
        email_placeholders=_list("GIR_EMAIL_PLACEHOLDERS", Settings.email_placeholders),
        email_placeholder_patterns=tuple(x for x in os.environ.get("GIR_EMAIL_PLACEHOLDER_PATTERNS", "").split("||") if x)
        or Settings.email_placeholder_patterns,
        accept_empty_agency=_flag("GIR_DIRECT_ACCEPT_EMPTY_AGENCY", False),
        phone_966_without_plus_is_e164=_flag("GIR_PHONE_966_WITHOUT_PLUS_IS_E164", True),
        phone_saudi_local_without_context=os.environ.get("GIR_PHONE_SAUDI_LOCAL_WITHOUT_CONTEXT", "MEDIUM").upper(),
        phone_default_region=os.environ.get("GIR_PHONE_DEFAULT_REGION") or None,
        over_shared_phone_threshold=int(os.environ.get("GIR_OVER_SHARED_PHONE_THRESHOLD", "5")),
        over_shared_email_threshold=int(os.environ.get("GIR_OVER_SHARED_EMAIL_THRESHOLD", "5")),
        id_allocation_strategy=os.environ.get("GIR_ID_ALLOCATION_STRATEGY", "MULE_COMPAT"),
        loyalty_id_prefix=os.environ.get("GIR_LOYALTY_ID_PREFIX", "12"),
        loyalty_id_random_digits=int(os.environ.get("GIR_LOYALTY_ID_RANDOM_DIGITS", "7")),
        id_allocation_max_attempts=int(os.environ.get("GIR_ID_ALLOCATION_MAX_ATTEMPTS", "5")),
        global_id_format=os.environ.get("GIR_GLOBAL_ID_FORMAT", "G{n:08d}"),
        loyalty_id_format=os.environ.get("GIR_LOYALTY_ID_FORMAT", "L{n:08d}"),
        candidate_guardrail=int(os.environ.get("GIR_CANDIDATE_GUARDRAIL", "100")),
        docs_enabled=_flag("GIR_DOCS_ENABLED", False),
        rate_limit_per_minute=int(os.environ.get("GIR_RATE_LIMIT_PER_MINUTE", "0")),
        sla_conflict_days=int(os.environ.get("GIR_SLA_CONFLICT_DAYS", "1")),
        sla_four_field_days=int(os.environ.get("GIR_SLA_FOUR_FIELD_DAYS", "2")),
        work_week=tuple(int(x) for x in _list("GIR_WORK_WEEK", ("6", "0", "1", "2", "3"))),
        database_schema=os.environ.get("GIR_DATABASE_SCHEMA", "gir"),
        db_host=os.environ.get("GIR_DB_HOST", ""),
        db_port=int(os.environ.get("GIR_DB_PORT", "5432")),
        db_name=os.environ.get("GIR_DB_NAME", ""),
        db_user=os.environ.get("GIR_DB_USER", ""),
        db_sslmode=os.environ.get("GIR_DB_SSLMODE", "verify-full"),
        db_sslrootcert=os.environ.get("GIR_DB_SSLROOTCERT", ""),
        db_pool_size=int(os.environ.get("GIR_DB_POOL_SIZE", "5")),
        db_max_overflow=int(os.environ.get("GIR_DB_MAX_OVERFLOW", "5")),
        app_db_role=os.environ.get("GIR_APP_DB_ROLE", ""),
        db_password=_secret("GIR_DB_PASSWORD"),
        database_url=_secret("GIR_DATABASE_URL"),
        data_key_b64=_secret("GIR_DATA_KEY"),
        data_key_id=os.environ.get("GIR_DATA_KEY_ID", "k1"),
        hmac_key_b64=_secret("GIR_HMAC_KEY"),
        service_token=_secret("GIR_SERVICE_TOKEN"),
    )


def database_url(s: Settings):
    """The connection URL: GIR_DATABASE_URL if given (tests), else built from the parts. The
    password is passed as a URL object attribute - it is never formatted into logs or errors."""
    from sqlalchemy.engine import URL, make_url
    if s.database_url:
        return make_url(s.database_url)
    if not (s.db_host and s.db_name and s.db_user):
        raise RuntimeError("database connection is not configured (GIR_DB_HOST / GIR_DB_NAME / GIR_DB_USER)")
    query = {"sslmode": s.db_sslmode, "application_name": "guest-identity-resolution-api"}
    if s.db_sslrootcert:
        query["sslrootcert"] = s.db_sslrootcert
    return URL.create("postgresql+psycopg", username=s.db_user, password=s.db_password or None,
                      host=s.db_host, port=s.db_port, database=s.db_name, query=query)
