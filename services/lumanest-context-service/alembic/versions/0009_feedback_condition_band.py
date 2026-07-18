"""Add the qualitative condition band used for feedback calibration."""

from alembic import op
import sqlalchemy as sa


revision = "0009_feedback_condition_band"
down_revision = "0008_traceable_shooting_targets"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "shooting_session_feedback",
        sa.Column("condition_band", sa.String(length=16), nullable=True),
    )
    op.create_check_constraint(
        "ck_shooting_feedback_condition_band",
        "shooting_session_feedback",
        "condition_band IS NULL OR condition_band IN ('good', 'fair', 'limited')",
    )
    op.create_index(
        "ix_shooting_feedback_calibration",
        "shooting_session_feedback",
        ["rule_version", "condition_band", "received_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_shooting_feedback_calibration",
        table_name="shooting_session_feedback",
    )
    op.drop_constraint(
        "ck_shooting_feedback_condition_band",
        "shooting_session_feedback",
        type_="check",
    )
    op.drop_column("shooting_session_feedback", "condition_band")
