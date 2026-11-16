"""Table definitions used by the repositories (SQLAlchemy Core). The schema itself is created by
the Alembic migration migrations/versions/0001_initial.py; tests/integration/test_schema.py
proves both agree. Tables follow plan section 8.1/8.2; review_decision is an implementation
extension holding prepared manual decisions (section 9.7)."""
from __future__ import annotations

from sqlalchemy import (Boolean, Column, Date, DateTime, Integer, LargeBinary, MetaData, String, Table, Text)
from sqlalchemy.dialects.postgresql import JSONB, UUID

metadata = MetaData()

guest_match_index = Table(
    "guest_match_index", metadata,
    Column("crm_guest_record_id", String, primary_key=True),
    Column("crm_identity_record_id", String),
    Column("identity_id", UUID(as_uuid=False)),
    Column("source_system", String, nullable=False),
    Column("source_record_id", String, nullable=False),
    Column("source_first_name_enc", LargeBinary),
    Column("source_last_name_enc", LargeBinary),
    Column("source_dob_enc", LargeBinary),
    Column("source_phone_enc", LargeBinary),
    Column("source_email_enc", LargeBinary),
    Column("canonical_first_name", String),
    Column("canonical_last_name", String),
    Column("dob_key", Date),
    Column("dob_is_placeholder", Boolean, nullable=False),
    Column("phone_e164_key", String),
    Column("phone_tail_key", String),
    Column("phone_confidence", String),
    Column("email_key", String),
    Column("active_flag", Boolean, nullable=False),
    Column("direct_scope_flag", Boolean, nullable=False),
    Column("crm_modified_time", DateTime(timezone=True), nullable=False),
    Column("indexed_time", DateTime(timezone=True), nullable=False),
    Column("source_alt_phone_enc", LargeBinary),
    Column("alt_phone_e164_key", String),
    Column("alt_phone_tail_key", String),
    Column("alt_phone_confidence", String),
)

identity_projection = Table(
    "identity_projection", metadata,
    Column("identity_id", UUID(as_uuid=False), primary_key=True),
    Column("crm_identity_record_id", String),
    Column("global_id_enc", LargeBinary),
    Column("loyalty_id_enc", LargeBinary),
    Column("global_id_hash", String),
    Column("loyalty_id_hash", String),
    Column("pair_integrity", String, nullable=False),
    Column("lifecycle_status", String, nullable=False),
    Column("committed", Boolean, nullable=False),
    Column("surviving_identity_id", UUID(as_uuid=False)),
    Column("created_by_process", String, nullable=False),
    Column("rule_version", String, nullable=False),
    Column("reserved_by_decision_id", String),
    Column("created_time", DateTime(timezone=True), nullable=False),
    Column("modified_time", DateTime(timezone=True), nullable=False),
)

processing_request = Table(
    "processing_request", metadata,
    Column("request_id", UUID(as_uuid=False), primary_key=True),
    Column("idempotency_key", String, nullable=False),
    Column("payload_hash", String, nullable=False),
    Column("kind", String, nullable=False),
    Column("crm_guest_record_id", String, nullable=False),
    Column("correlation_id", String, nullable=False),
    Column("state", String, nullable=False),
    Column("attempts", Integer, nullable=False),
    Column("decision_id", String),
    Column("error_code", String),
    Column("created_time", DateTime(timezone=True), nullable=False),
    Column("updated_time", DateTime(timezone=True), nullable=False),
)

identity_decision = Table(
    "identity_decision", metadata,
    Column("decision_id", String, primary_key=True),
    Column("request_id", UUID(as_uuid=False), nullable=False),
    Column("crm_guest_record_id", String, nullable=False),
    Column("decision", String, nullable=False),
    Column("decision_type", String, nullable=False),
    Column("identity_status", String, nullable=False),
    Column("identity_id", UUID(as_uuid=False)),
    Column("reserved_new_pair", Boolean, nullable=False),
    Column("review_required", Boolean, nullable=False),
    Column("review_case_id", String),
    Column("crm_update_required", Boolean, nullable=False),
    Column("rule_version", String, nullable=False),
    Column("rule_checksum", String, nullable=False),
    Column("reason_codes", JSONB, nullable=False),
    Column("candidate_refs", JSONB, nullable=False),
    Column("shadow", JSONB),
    Column("summary", Text, nullable=False),
    Column("state", String, nullable=False),
    Column("correlation_id", String, nullable=False),
    Column("error_code", String),
    Column("created_time", DateTime(timezone=True), nullable=False),
    Column("updated_time", DateTime(timezone=True), nullable=False),
)

identifier_statistics = Table(
    "identifier_statistics", metadata,
    Column("key_type", String, primary_key=True),
    Column("key_value", String, primary_key=True),
    Column("distinct_identity_count", Integer, nullable=False),
    Column("over_shared", Boolean, nullable=False),
    Column("threshold_version", String, nullable=False),
    Column("updated_time", DateTime(timezone=True), nullable=False),
)

review_case_projection = Table(
    "review_case_projection", metadata,
    Column("case_id", String, primary_key=True),
    Column("crm_guest_record_id", String, nullable=False),
    Column("provisional_identity_id", UUID(as_uuid=False)),
    Column("source_decision_id", String, nullable=False),
    Column("kind", String, nullable=False),
    Column("priority", String, nullable=False),
    Column("state", String, nullable=False),
    Column("last_result", String),
    Column("rule_version", String, nullable=False),
    Column("reason_codes", JSONB, nullable=False),
    Column("assigned_to", String),
    Column("follow_up_date", Date),
    Column("created_time", DateTime(timezone=True), nullable=False),
    Column("updated_time", DateTime(timezone=True), nullable=False),
)

review_candidate = Table(
    "review_candidate", metadata,
    Column("case_id", String, primary_key=True),
    Column("crm_guest_record_id", String, primary_key=True),
    Column("rank", Integer, nullable=False),
    Column("identity_id", UUID(as_uuid=False)),
    Column("crm_identity_record_id", String),
    Column("field_results", JSONB, nullable=False),
    Column("reason_codes", JSONB, nullable=False),
    Column("shadow", JSONB),
)

review_decision = Table(
    "review_decision", metadata,
    Column("review_decision_id", String, primary_key=True),
    Column("case_id", String, nullable=False),
    Column("idempotency_key", String, nullable=False),
    Column("reviewer_id", String, nullable=False),
    Column("action", String, nullable=False),
    Column("selected_identity_id", UUID(as_uuid=False)),
    Column("comment", Text),
    Column("versions_shown", JSONB, nullable=False),
    Column("crm_records_to_check", JSONB, nullable=False),
    Column("crm_patch", JSONB, nullable=False),
    Column("state", String, nullable=False),
    Column("error_code", String),
    Column("created_time", DateTime(timezone=True), nullable=False),
    Column("updated_time", DateTime(timezone=True), nullable=False),
)

rule_version = Table(
    "rule_version", metadata,
    Column("version", String, primary_key=True),
    Column("effective_time", DateTime(timezone=True), nullable=False),
    Column("checksum", String, nullable=False),
    Column("status", String, nullable=False),
    Column("configuration", JSONB, nullable=False),
)

reconciliation_state = Table(
    "reconciliation_state", metadata,
    Column("job", String, primary_key=True),
    Column("watermark", DateTime(timezone=True)),
    Column("last_result", String),
    Column("counts", JSONB),
    Column("failure_details", JSONB),
    Column("updated_time", DateTime(timezone=True), nullable=False),
)

bootstrap_batch = Table(
    "bootstrap_batch", metadata,
    Column("batch_id", String, primary_key=True),
    Column("payload_hash", String, nullable=False),
    Column("received", Integer, nullable=False),
    Column("counts", JSONB, nullable=False),
    Column("duration_ms", Integer, nullable=False),
    Column("created_time", DateTime(timezone=True), nullable=False),
)
