"""Bootstrap batches (plan section 16): idempotent bulk index loads.

Revision ID: 0002_bootstrap
Revises: 0001_initial
"""
from alembic import op

revision = "0002_bootstrap"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
CREATE TABLE bootstrap_batch (
  batch_id      varchar PRIMARY KEY,
  payload_hash  varchar NOT NULL,
  received      integer NOT NULL,
  counts        jsonb NOT NULL,
  duration_ms   integer NOT NULL,
  created_time  timestamptz NOT NULL
);
CREATE INDEX gmi_pending ON guest_match_index (crm_guest_record_id)
  WHERE identity_id IS NULL AND active_flag AND direct_scope_flag;
""")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS gmi_pending; DROP TABLE IF EXISTS bootstrap_batch;")
