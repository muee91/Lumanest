"""Persist source-linked regional insights without requiring a place coordinate."""

from alembic import op
import sqlalchemy as sa


revision = "0005_region_insights"
down_revision = "0004_source_revisions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "region_entities",
        sa.Column("id", sa.String(80), primary_key=True),
        sa.Column("canonical_key", sa.String(256), nullable=False, unique=True),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("locale", sa.String(16), nullable=False),
        # The centre is a coarse grid reference used for bounded retrieval,
        # never an application GPS trace.
        sa.Column("center_latitude", sa.Float(), nullable=False),
        sa.Column("center_longitude", sa.Float(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("center_latitude BETWEEN -90 AND 90", name="ck_discovery_region_latitude"),
        sa.CheckConstraint("center_longitude BETWEEN -180 AND 180", name="ck_discovery_region_longitude"),
        schema="discovery",
    )
    op.create_index("ix_discovery_region_entities_locale", "region_entities", ["locale", "updated_at"], schema="discovery")
    op.create_table(
        "region_insights",
        sa.Column("id", sa.String(80), primary_key=True),
        sa.Column("region_id", sa.String(80), sa.ForeignKey("discovery.region_entities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("place_id", sa.String(64), sa.ForeignKey("discovery.places.id", ondelete="SET NULL")),
        sa.Column("kind", sa.String(32), nullable=False),
        sa.Column("title", sa.String(160), nullable=False),
        sa.Column("summary", sa.String(600), nullable=False),
        sa.Column("verification", sa.String(24), nullable=False),
        sa.Column("actionability", sa.String(16), nullable=False, server_default="informational"),
        sa.Column("time_sensitive", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("scene_tags", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("photo_theme_tags", sa.JSON(), nullable=False, server_default="[]"),
        sa.Column("starts_at", sa.DateTime(timezone=True)),
        sa.Column("ends_at", sa.DateTime(timezone=True)),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("kind IN ('areaIdentity','orientation','history','localStory','architecture','culturalPractice','etiquette','performance','event','market','localFood','specialty','naturalFeature','photographyTheme','routeStop','supply','openingStatus','regulation','seasonalSignal')", name="ck_discovery_region_insight_kind"),
        sa.CheckConstraint("verification IN ('authoritative','corroborated','singleSource','candidate','conflicting')", name="ck_discovery_region_insight_verification"),
        sa.CheckConstraint("actionability IN ('informational','detail','navigate','remind')", name="ck_discovery_region_insight_actionability"),
        sa.CheckConstraint("expires_at > observed_at", name="ck_discovery_region_insight_expiry"),
        schema="discovery",
    )
    op.create_index("ix_discovery_region_insights_active", "region_insights", ["region_id", "expires_at", "updated_at"], schema="discovery")
    op.create_table(
        "region_insight_facts",
        sa.Column("id", sa.String(80), primary_key=True),
        sa.Column("insight_id", sa.String(80), sa.ForeignKey("discovery.region_insights.id", ondelete="CASCADE"), nullable=False),
        sa.Column("claim_fingerprint", sa.String(80), nullable=False),
        sa.Column("claim_text", sa.String(600), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("insight_id", "claim_fingerprint", name="uq_discovery_region_fact"),
        schema="discovery",
    )
    op.create_table(
        "region_insight_evidence",
        sa.Column("insight_id", sa.String(80), sa.ForeignKey("discovery.region_insights.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source_document_id", sa.String(64), sa.ForeignKey("discovery.source_documents.id", ondelete="CASCADE"), nullable=False),
        sa.Column("quality_tier", sa.String(1), nullable=False),
        sa.Column("license", sa.String(160), nullable=False),
        sa.PrimaryKeyConstraint("insight_id", "source_document_id", name="pk_discovery_region_insight_evidence"),
        sa.CheckConstraint("quality_tier IN ('S','A','B','C')", name="ck_discovery_region_evidence_tier"),
        schema="discovery",
    )


def downgrade() -> None:
    op.drop_table("region_insight_evidence", schema="discovery")
    op.drop_table("region_insight_facts", schema="discovery")
    op.drop_index("ix_discovery_region_insights_active", table_name="region_insights", schema="discovery")
    op.drop_table("region_insights", schema="discovery")
    op.drop_index("ix_discovery_region_entities_locale", table_name="region_entities", schema="discovery")
    op.drop_table("region_entities", schema="discovery")
