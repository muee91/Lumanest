"""Add an explicit, reviewed static-photography-target marker.

Only public Point features imported with target_type may be returned as a
PhotographyTarget.  The target remains in the existing source licensing model.
"""

from alembic import op
import sqlalchemy as sa


revision = "0005_photography_targets"
down_revision = "0004_nasa_meteor_catalog_2026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("spatial_features", sa.Column("target_type", sa.String(16), nullable=True))
    op.create_check_constraint(
        "ck_spatial_features_target_type",
        "spatial_features",
        "target_type IS NULL OR target_type IN ('viewpoint', 'lakeshore', 'trailhead', 'urban')",
    )
    op.execute("""
        CREATE INDEX ix_spatial_features_photography_target
        ON spatial_features (target_type)
        WHERE target_type IS NOT NULL
    """)


def downgrade() -> None:
    op.drop_index("ix_spatial_features_photography_target", table_name="spatial_features")
    op.drop_constraint("ck_spatial_features_target_type", "spatial_features", type_="check")
    op.drop_column("spatial_features", "target_type")
