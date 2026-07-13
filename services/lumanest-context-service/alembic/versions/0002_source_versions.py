"""Add traceable source versions."""

from alembic import op
import sqlalchemy as sa


revision = "0002_source_versions"
down_revision = "0001_context_foundation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "source_registry",
        sa.Column("dataset_type", sa.String(32), nullable=False, server_default="unknown"),
    )
    op.add_column(
        "source_registry",
        sa.Column("version", sa.String(100), nullable=False, server_default="unversioned"),
    )
    op.add_column(
        "spatial_features",
        sa.Column("external_id", sa.String(128), nullable=True),
    )
    op.add_column(
        "astronomy_events",
        sa.Column("external_id", sa.String(128), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("astronomy_events", "external_id")
    op.drop_column("spatial_features", "external_id")
    op.drop_column("source_registry", "version")
    op.drop_column("source_registry", "dataset_type")
