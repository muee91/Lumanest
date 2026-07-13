"""Create the source registry and spatial context foundation."""

from alembic import op
import sqlalchemy as sa


revision = "0001_context_foundation"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.create_table(
        "source_registry",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("license_status", sa.String(16), nullable=False),
        sa.Column("attribution", sa.String(500), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("license_status IN ('approved','pending','disabled')"),
    )
    op.create_table(
        "spatial_features",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("source_id", sa.String(64), sa.ForeignKey("source_registry.id"), nullable=False),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("sensitivity", sa.String(16), nullable=False, server_default="public"),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("valid_from", sa.DateTime(timezone=True)),
        sa.Column("valid_until", sa.DateTime(timezone=True)),
    )
    op.execute("ALTER TABLE spatial_features ADD COLUMN geometry geometry(Geometry, 4326) NOT NULL")
    op.execute("CREATE INDEX ix_spatial_features_geometry ON spatial_features USING GIST (geometry)")
    op.create_table(
        "astronomy_events",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("source_id", sa.String(64), sa.ForeignKey("source_registry.id"), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("source_url", sa.String(500), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_table(
        "rule_versions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("rule_versions")
    op.drop_table("astronomy_events")
    op.drop_table("spatial_features")
    op.drop_table("source_registry")
