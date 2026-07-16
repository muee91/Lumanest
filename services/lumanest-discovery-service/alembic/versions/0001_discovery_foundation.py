"""Create isolated canonical discovery and evidence storage."""

from alembic import op
import sqlalchemy as sa


revision = "0001_discovery_foundation"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE SCHEMA IF NOT EXISTS discovery")
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.create_table(
        "places",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("canonical_key", sa.String(256), nullable=False, unique=True),
        sa.Column("kind", sa.String(24), nullable=False),
        sa.Column("name", sa.String(240), nullable=False),
        sa.Column("summary", sa.String(600)),
        sa.Column("address", sa.String(300)),
        sa.Column("verification", sa.String(16), nullable=False, server_default="candidate"),
        sa.Column("published", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("valid_until", sa.DateTime(timezone=True)),
        sa.Column("starts_at", sa.DateTime(timezone=True)),
        sa.Column("ends_at", sa.DateTime(timezone=True)),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("kind IN ('candidate_viewpoint','attraction','event')", name="ck_discovery_places_kind"),
        sa.CheckConstraint("verification IN ('candidate','verified')", name="ck_discovery_places_verification"),
        schema="discovery",
    )
    op.execute("ALTER TABLE discovery.places ADD COLUMN geometry geometry(Point, 4326) NOT NULL")
    op.execute("CREATE INDEX ix_discovery_places_geometry ON discovery.places USING GIST (geometry)")
    op.create_index("ix_discovery_places_public_valid", "places", ["published", "valid_until"], schema="discovery")
    op.create_table(
        "evidence",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("place_id", sa.String(64), sa.ForeignKey("discovery.places.id", ondelete="CASCADE"), nullable=False),
        sa.Column("provider", sa.String(80), nullable=False),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("source_url", sa.String(1000), nullable=False),
        sa.Column("license", sa.String(160), nullable=False),
        sa.Column("review_status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("retrieved_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True)),
        sa.CheckConstraint("review_status IN ('approved','pending','disabled')", name="ck_discovery_evidence_review"),
        schema="discovery",
    )
    op.create_index("ix_discovery_evidence_place_review", "evidence", ["place_id", "review_status"], schema="discovery")
    op.create_table(
        "region_refreshes",
        sa.Column("fingerprint", sa.String(64), primary_key=True),
        sa.Column("state", sa.String(16), nullable=False),
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("state IN ('pending','attempted','failed')", name="ck_discovery_refresh_state"),
        schema="discovery",
    )


def downgrade() -> None:
    op.drop_table("region_refreshes", schema="discovery")
    op.drop_table("evidence", schema="discovery")
    op.drop_table("places", schema="discovery")
    # discovery_alembic_version intentionally remains in this namespace.
