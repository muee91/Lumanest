"""Store bounded anonymous shooting-session feedback."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0007_shooting_session_feedback"
down_revision = "0006_shooting_session_targets"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "shooting_session_feedback",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rule_version", sa.String(length=32), nullable=False),
        sa.Column(
            "factors",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
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
    )
    op.create_index(
        "ix_shooting_feedback_received_at",
        "shooting_session_feedback",
        ["received_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_shooting_feedback_received_at",
        table_name="shooting_session_feedback",
    )
    op.drop_table("shooting_session_feedback")
