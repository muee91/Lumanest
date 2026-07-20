"""Align refresh focus storage with the current discovery request contract."""

from alembic import op
import sqlalchemy as sa


revision = "0003_freshness_focus"
down_revision = "0002_discovery_ingest_evidence"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "region_refreshes",
        "focus",
        existing_type=sa.String(length=24),
        type_=sa.String(length=180),
        existing_nullable=True,
        schema="discovery",
    )


def downgrade() -> None:
    op.alter_column(
        "region_refreshes",
        "focus",
        existing_type=sa.String(length=180),
        type_=sa.String(length=24),
        existing_nullable=True,
        schema="discovery",
    )
