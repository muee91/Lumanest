"""Require traceable licensing and shoreline review for shooting targets."""

from alembic import op
import sqlalchemy as sa


revision = "0008_traceable_shooting_targets"
down_revision = "0007_shooting_session_feedback"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("source_registry", sa.Column("license_id", sa.String(100), nullable=True))
    op.add_column("source_registry", sa.Column("source_url", sa.Text(), nullable=True))
    op.add_column("source_registry", sa.Column("license_url", sa.Text(), nullable=True))
    op.add_column("spatial_features", sa.Column("shoreline_side", sa.String(16), nullable=True))
    op.add_column("spatial_features", sa.Column("review_reference", sa.Text(), nullable=True))
    op.create_check_constraint(
        "ck_spatial_features_shooting_target_traceable",
        "spatial_features",
        """
        shooting_session_target = FALSE OR (
            shoreline_side IN (
                'north', 'northeast', 'east', 'southeast',
                'south', 'southwest', 'west', 'northwest'
            )
            AND review_reference IS NOT NULL
            AND length(trim(review_reference)) > 0
        )
        """,
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_spatial_features_shooting_target_traceable",
        "spatial_features",
        type_="check",
    )
    op.drop_column("spatial_features", "review_reference")
    op.drop_column("spatial_features", "shoreline_side")
    op.drop_column("source_registry", "license_url")
    op.drop_column("source_registry", "source_url")
    op.drop_column("source_registry", "license_id")
