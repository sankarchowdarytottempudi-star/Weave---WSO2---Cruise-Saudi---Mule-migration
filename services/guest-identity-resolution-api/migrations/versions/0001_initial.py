"""Initial schema: plan section 8 (tables, constraints, indexes, state checks).

Revision ID: 0001_initial
Revises:
"""
from alembic import op

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None

PROCESSING = "('RECEIVED','DECIDED_PENDING_CRM','COMMITTED','CRM_UPDATE_FAILED','REJECTED_STALE','FAILED')"
REVIEW = ("('REVIEW_OPEN','REVIEW_DECISION_PREPARED','REVIEW_DATA_CHANGED','REVIEW_CRM_UPDATE_PENDING',"
          "'REVIEW_COMMITTED','REVIEW_FAILED')")
LIFECYCLE = "('RESERVED','ACTIVE','PROVISIONAL','RETIRED','ALIAS','BLOCKED')"
INTEGRITY = "('COMPLETE','INCOMPLETE','CONFLICT')"
DECISIONS = ("('REUSE_EXISTING_IDENTITY','CREATE_NEW_IDENTITY','CREATE_PROVISIONAL_IDENTITY',"
             "'KEEP_EXISTING_IDENTITY','EXCLUDED_NON_DIRECT')")
ACTIONS = "('CONFIRM_SAME_PERSON','CONFIRM_DIFFERENT_PEOPLE','CONFIRM_HOUSEHOLD','DEFER','REVERSE_DECISION')"

UP = f"""
CREATE SEQUENCE gir_pair_seq START 1 INCREMENT 1;

CREATE TABLE identity_projection (
  identity_id            uuid PRIMARY KEY,
  crm_identity_record_id varchar UNIQUE,
  global_id_enc          bytea,
  loyalty_id_enc         bytea,
  global_id_hash         varchar UNIQUE,
  loyalty_id_hash        varchar UNIQUE,
  pair_integrity         varchar NOT NULL CHECK (pair_integrity IN {INTEGRITY}),
  lifecycle_status       varchar NOT NULL CHECK (lifecycle_status IN {LIFECYCLE}),
  committed              boolean NOT NULL DEFAULT false,
  surviving_identity_id  uuid REFERENCES identity_projection(identity_id),
  created_by_process     varchar NOT NULL CHECK (created_by_process IN ('BASELINE','CERTAIN','NEW','REVIEW','MANUAL')),
  rule_version           varchar NOT NULL,
  reserved_by_decision_id varchar UNIQUE,
  created_time           timestamptz NOT NULL,
  modified_time          timestamptz NOT NULL,
  CHECK (pair_integrity <> 'COMPLETE' OR (global_id_hash IS NOT NULL AND loyalty_id_hash IS NOT NULL))
);

CREATE TABLE guest_match_index (
  crm_guest_record_id    varchar PRIMARY KEY,
  crm_identity_record_id varchar NULL,
  identity_id            uuid NULL REFERENCES identity_projection(identity_id),
  source_system          varchar NOT NULL,
  source_record_id       varchar NOT NULL,
  source_first_name_enc  bytea,
  source_last_name_enc   bytea,
  source_dob_enc         bytea,
  source_phone_enc       bytea,
  source_email_enc       bytea,
  canonical_first_name   varchar,
  canonical_last_name    varchar,
  dob_key                date,
  dob_is_placeholder     boolean NOT NULL,
  phone_e164_key         varchar,
  phone_tail_key         varchar,
  phone_confidence       varchar,
  email_key              varchar,
  active_flag            boolean NOT NULL,
  direct_scope_flag      boolean NOT NULL,
  crm_modified_time      timestamptz NOT NULL,
  indexed_time           timestamptz NOT NULL,
  UNIQUE (source_system, source_record_id)
);
CREATE INDEX gmi_names_dob ON guest_match_index (canonical_first_name, canonical_last_name, dob_key);
CREATE INDEX gmi_phone ON guest_match_index (phone_e164_key) WHERE phone_e164_key IS NOT NULL;
CREATE INDEX gmi_phone_tail ON guest_match_index (phone_tail_key) WHERE phone_tail_key IS NOT NULL;
CREATE INDEX gmi_email ON guest_match_index (email_key) WHERE email_key IS NOT NULL;
CREATE INDEX gmi_identity ON guest_match_index (identity_id);
CREATE INDEX gmi_dob ON guest_match_index (dob_key) WHERE dob_key IS NOT NULL;

CREATE TABLE processing_request (
  request_id          uuid PRIMARY KEY,
  idempotency_key     varchar NOT NULL UNIQUE,
  payload_hash        varchar NOT NULL,
  kind                varchar NOT NULL CHECK (kind IN ('EVALUATE','REEVALUATE')),
  crm_guest_record_id varchar NOT NULL,
  correlation_id      varchar NOT NULL,
  state               varchar NOT NULL CHECK (state IN {PROCESSING}),
  attempts            integer NOT NULL DEFAULT 1,
  decision_id         varchar,
  error_code          varchar,
  created_time        timestamptz NOT NULL,
  updated_time        timestamptz NOT NULL
);

CREATE TABLE identity_decision (
  decision_id         varchar PRIMARY KEY,
  request_id          uuid NOT NULL REFERENCES processing_request(request_id),
  crm_guest_record_id varchar NOT NULL,
  decision            varchar NOT NULL CHECK (decision IN {DECISIONS}),
  decision_type       varchar NOT NULL,
  identity_status     varchar NOT NULL,
  identity_id         uuid REFERENCES identity_projection(identity_id),
  reserved_new_pair   boolean NOT NULL,
  review_required     boolean NOT NULL,
  review_case_id      varchar,
  crm_update_required boolean NOT NULL,
  rule_version        varchar NOT NULL,
  rule_checksum       varchar NOT NULL,
  reason_codes        jsonb NOT NULL,
  candidate_refs      jsonb NOT NULL,
  shadow              jsonb,
  summary             text NOT NULL,
  state               varchar NOT NULL CHECK (state IN {PROCESSING}),
  correlation_id      varchar NOT NULL,
  error_code          varchar,
  created_time        timestamptz NOT NULL,
  updated_time        timestamptz NOT NULL
);
CREATE INDEX idec_guest ON identity_decision (crm_guest_record_id);
CREATE INDEX idec_state ON identity_decision (state);

CREATE TABLE identifier_statistics (
  key_type                varchar NOT NULL CHECK (key_type IN ('PHONE','EMAIL','DOB')),
  key_value               varchar NOT NULL,
  distinct_identity_count integer NOT NULL,
  over_shared             boolean NOT NULL,
  threshold_version       varchar NOT NULL,
  updated_time            timestamptz NOT NULL,
  PRIMARY KEY (key_type, key_value)
);

CREATE TABLE review_case_projection (
  case_id                 varchar PRIMARY KEY,
  crm_guest_record_id     varchar NOT NULL,
  provisional_identity_id uuid REFERENCES identity_projection(identity_id),
  source_decision_id      varchar NOT NULL REFERENCES identity_decision(decision_id),
  kind                    varchar NOT NULL,
  priority                varchar NOT NULL CHECK (priority IN ('HIGH','NORMAL')),
  state                   varchar NOT NULL CHECK (state IN {REVIEW}),
  last_result             varchar,
  rule_version            varchar NOT NULL,
  reason_codes            jsonb NOT NULL,
  assigned_to             varchar,
  follow_up_date          date,
  created_time            timestamptz NOT NULL,
  updated_time            timestamptz NOT NULL
);
CREATE INDEX rcp_queue ON review_case_projection (state, priority, created_time);

CREATE TABLE review_candidate (
  case_id                varchar NOT NULL REFERENCES review_case_projection(case_id) ON DELETE CASCADE,
  crm_guest_record_id    varchar NOT NULL,
  rank                   integer NOT NULL,
  identity_id            uuid,
  crm_identity_record_id varchar,
  field_results          jsonb NOT NULL,
  reason_codes           jsonb NOT NULL,
  shadow                 jsonb,
  PRIMARY KEY (case_id, crm_guest_record_id)
);

CREATE TABLE review_decision (
  review_decision_id   varchar PRIMARY KEY,
  case_id              varchar NOT NULL REFERENCES review_case_projection(case_id),
  idempotency_key      varchar NOT NULL UNIQUE,
  reviewer_id          varchar NOT NULL,
  action               varchar NOT NULL CHECK (action IN {ACTIONS}),
  selected_identity_id uuid,
  comment              text,
  versions_shown       jsonb NOT NULL,
  crm_records_to_check jsonb NOT NULL,
  crm_patch            jsonb NOT NULL,
  state                varchar NOT NULL CHECK (state IN {REVIEW}),
  error_code           varchar,
  created_time         timestamptz NOT NULL,
  updated_time         timestamptz NOT NULL
);

CREATE TABLE rule_version (
  version        varchar PRIMARY KEY,
  effective_time timestamptz NOT NULL,
  checksum       varchar NOT NULL,
  status         varchar NOT NULL CHECK (status IN ('ACTIVE','RETIRED','DRAFT')),
  configuration  jsonb NOT NULL
);

CREATE TABLE reconciliation_state (
  job             varchar PRIMARY KEY,
  watermark       timestamptz,
  last_result     varchar,
  counts          jsonb,
  failure_details jsonb,
  updated_time    timestamptz NOT NULL
);
"""

DOWN = """
DROP TABLE IF EXISTS reconciliation_state, rule_version, review_decision, review_candidate,
  review_case_projection, identifier_statistics, identity_decision, processing_request,
  guest_match_index, identity_projection CASCADE;
DROP SEQUENCE IF EXISTS gir_pair_seq;
"""


def upgrade() -> None:
    op.execute(UP)


def downgrade() -> None:
    op.execute(DOWN)
