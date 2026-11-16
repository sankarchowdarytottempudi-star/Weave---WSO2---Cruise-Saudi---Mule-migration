"""Review Workbench support: SLA due time, case history (no personal details), comments.

Revision ID: 0004_review_workbench
Revises: 0003_alternate_phone
"""
from alembic import op

revision = "0004_review_workbench"
down_revision = "0003_alternate_phone"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
ALTER TABLE review_case_projection ADD COLUMN sla_due_time timestamptz;
CREATE INDEX rcp_assignee ON review_case_projection (assigned_to, state);
CREATE TABLE review_case_event (
  event_id     bigserial PRIMARY KEY,
  case_id      varchar NOT NULL REFERENCES review_case_projection(case_id) ON DELETE CASCADE,
  event_type   varchar NOT NULL CHECK (event_type IN ('CREATED','ASSIGNED','COMMENTED','DECISION_PREPARED',
               'DATA_CHANGED','CRM_UPDATE_PENDING','COMMITTED','FAILED','REOPENED')),
  actor_id     varchar,
  details      jsonb NOT NULL,
  created_time timestamptz NOT NULL
);
CREATE INDEX rce_case ON review_case_event (case_id, event_id);
CREATE TABLE review_comment (
  comment_id   varchar PRIMARY KEY,
  case_id      varchar NOT NULL REFERENCES review_case_projection(case_id) ON DELETE CASCADE,
  author_id    varchar NOT NULL,
  text_enc     bytea NOT NULL,
  created_time timestamptz NOT NULL
);
CREATE INDEX rcm_case ON review_comment (case_id, created_time);
""")


def downgrade() -> None:
    op.execute("""
DROP TABLE IF EXISTS review_comment; DROP TABLE IF EXISTS review_case_event;
DROP INDEX IF EXISTS rcp_assignee; ALTER TABLE review_case_projection DROP COLUMN IF EXISTS sla_due_time;
""")
