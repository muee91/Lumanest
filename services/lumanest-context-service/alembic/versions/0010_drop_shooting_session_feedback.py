"""Drop the retired anonymous shooting feedback table.

Core 1.0 removed the shooting feedback/calibration product chain: the Flutter
opt-in switch, the Broker `/v1/context/shooting-feedback` route and the admin
calibration reader all no longer exist. The table is dropped here so stored
anonymous aggregates do not outlive the feature that promised their privacy
boundaries. Earlier feedback migrations stay in history for deployed databases.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0010_drop_shooting_session_feedback"
down_revision = "0009_feedback_condition_band"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_index(
        "ix_shooting_feedback_calibration",
        table_name="shooting_session_feedback",
    )
    op.drop_table("shooting_session_feedback")


def downgrade() -> None:
    # Recreates the exact 0007 + 0009 shape for databases rolling back before
    # this revision; downgrades past 0009 then continue through history.
    op.create_table(
        "shooting_session_feedback",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rule_version", sa.String(length=32), nullable=False),
        sa.Column("condition_band", sa.String(length=16), nullable=True),
        sa.Column("factors", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("outcome", sa.String(length=32), nullable=False),
        sa.Column(
            "reasons",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("target_id", sa.String(length=31), nullable=True),
        sa.CheckConstraint(
            "outcome IN ('captured', 'conditionsDidNotAppear', 'arrivedLate', 'didNotGo')",
            name="ck_shooting_feedback_outcome",
        ),
        sa.CheckConstraint(
            "jsonb_array_length(factors) BETWEEN 1 AND 8",
            name="ck_shooting_feedback_factors",
        ),
        sa.CheckConstraint(
            "jsonb_array_length(reasons) BETWEEN 0 AND 4",
            name="ck_shooting_feedback_reasons",
        ),
        sa.CheckConstraint(
            "target_id IS NULL OR target_id ~ '^target_[a-f0-9]{24}$'",
            name="ck_shooting_feedback_target_id",
        ),
        sa.CheckConstraint(
            "condition_band IS NULL OR condition_band IN ('good', 'fair', 'limited')",
            name="ck_shooting_feedback_condition_band",
        ),
    )
    op.create_index(
        "ix_shooting_feedback_calibration",
        "shooting_session_feedback",
        ["rule_version", "condition_band", "received_at"],
    )
