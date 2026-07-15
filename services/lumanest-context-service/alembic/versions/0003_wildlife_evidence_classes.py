"""Persist reviewed wildlife evidence classification."""

from alembic import op
import sqlalchemy as sa


revision = "0003_wildlife_evidence_classes"
down_revision = "0002_source_versions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "source_registry",
        sa.Column("category", sa.String(32), nullable=False, server_default="spatial"),
    )
    op.add_column(
        "spatial_features",
        sa.Column("evidence_class", sa.String(32), nullable=False, server_default="scene"),
    )
    op.create_check_constraint(
        "ck_source_registry_category",
        "source_registry",
        "category IN ('spatial','wildlifeHistorical','officialRisk')",
    )
    op.create_check_constraint(
        "ck_spatial_features_evidence_class",
        "spatial_features",
        "evidence_class IN ('scene','wildlifeOpportunity','wildlifeSafety')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_spatial_features_evidence_class", "spatial_features")
    op.drop_constraint("ck_source_registry_category", "source_registry")
    op.drop_column("spatial_features", "evidence_class")
    op.drop_column("source_registry", "category")
