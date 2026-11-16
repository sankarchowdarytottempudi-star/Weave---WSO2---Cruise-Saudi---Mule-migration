"""Second phone field (baseline finding: CRM Mobile and Phone both carry personal numbers).

Revision ID: 0003_alternate_phone
Revises: 0002_bootstrap
"""
from alembic import op

revision = "0003_alternate_phone"
down_revision = "0002_bootstrap"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
ALTER TABLE guest_match_index
  ADD COLUMN source_alt_phone_enc bytea,
  ADD COLUMN alt_phone_e164_key   varchar,
  ADD COLUMN alt_phone_tail_key   varchar,
  ADD COLUMN alt_phone_confidence varchar;
CREATE INDEX gmi_alt_phone ON guest_match_index (alt_phone_e164_key) WHERE alt_phone_e164_key IS NOT NULL;
CREATE INDEX gmi_alt_phone_tail ON guest_match_index (alt_phone_tail_key) WHERE alt_phone_tail_key IS NOT NULL;
""")


def downgrade() -> None:
    op.execute("""
DROP INDEX IF EXISTS gmi_alt_phone_tail; DROP INDEX IF EXISTS gmi_alt_phone;
ALTER TABLE guest_match_index DROP COLUMN alt_phone_confidence, DROP COLUMN alt_phone_tail_key,
  DROP COLUMN alt_phone_e164_key, DROP COLUMN source_alt_phone_enc;
""")
