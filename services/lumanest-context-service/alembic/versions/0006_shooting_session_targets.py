"""Add reviewed metadata for V4 shooting-session targets."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0006_shooting_session_targets"
down_revision = "0005_photography_targets"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "spatial_features",
        sa.Column("shooting_session_target", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "spatial_features",
        sa.Column(
            "supported_sessions",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column("spatial_features", sa.Column("view_bearing_degrees", sa.Float(), nullable=True))
    op.add_column("spatial_features", sa.Column("bearing_tolerance_degrees", sa.Float(), nullable=True))
    op.add_column(
        "spatial_features",
        sa.Column(
            "access_modes",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column("spatial_features", sa.Column("lead_time_minutes", sa.Integer(), nullable=True))
    op.add_column("spatial_features", sa.Column("arrival_radius_meters", sa.Integer(), nullable=True))
    op.add_column(
        "spatial_features",
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_check_constraint(
        "ck_spatial_features_shooting_target_complete",
        "spatial_features",
        """
        shooting_session_target = FALSE OR (
            target_type = 'lakeshore'
            AND jsonb_array_length(supported_sessions) > 0
            AND view_bearing_degrees >= 0 AND view_bearing_degrees < 360
            AND bearing_tolerance_degrees >= 5 AND bearing_tolerance_degrees <= 90
            AND jsonb_array_length(access_modes) > 0
            AND lead_time_minutes >= 0 AND lead_time_minutes <= 180
            AND arrival_radius_meters >= 25 AND arrival_radius_meters <= 1000
            AND reviewed_at IS NOT NULL
        )
        """,
    )
    op.execute("""
        CREATE INDEX ix_spatial_features_shooting_session_target
        ON spatial_features (shooting_session_target)
        WHERE shooting_session_target = TRUE
    """)


def downgrade() -> None:
    op.drop_index("ix_spatial_features_shooting_session_target", table_name="spatial_features")
    op.drop_constraint(
        "ck_spatial_features_shooting_target_complete",
        "spatial_features",
        type_="check",
    )
    for column in (
        "reviewed_at",
        "arrival_radius_meters",
        "lead_time_minutes",
        "access_modes",
        "bearing_tolerance_degrees",
        "view_bearing_degrees",
        "supported_sessions",
        "shooting_session_target",
    ):
        op.drop_column("spatial_features", column)
