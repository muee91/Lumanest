"""Add bounded coarse refresh references and evidence-linked source documents."""

from alembic import op
import sqlalchemy as sa


revision = "0002_discovery_ingestion_evidence"
down_revision = "0001_discovery_foundation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "source_documents",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("source_id", sa.String(80), nullable=False),
        sa.Column("source_version", sa.String(80), nullable=False),
        sa.Column("source_url", sa.String(1000), nullable=False, unique=True),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("snippet", sa.String(1200), nullable=False, server_default=""),
        sa.Column("publisher", sa.String(80), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True)),
        sa.Column("retrieved_at", sa.DateTime(timezone=True), nullable=False),
        schema="discovery",
    )
    op.add_column(
        "evidence",
        sa.Column("source_document_id", sa.String(64), sa.ForeignKey("discovery.source_documents.id", ondelete="CASCADE")),
        schema="discovery",
    )
    op.add_column("evidence", sa.Column("source_version", sa.String(80)), schema="discovery")
    op.create_index("ix_discovery_evidence_source_document", "evidence", ["source_document_id"], schema="discovery")
    op.add_column("region_refreshes", sa.Column("region_id", sa.String(80)), schema="discovery")
    op.add_column("region_refreshes", sa.Column("center_latitude", sa.Float()), schema="discovery")
    op.add_column("region_refreshes", sa.Column("center_longitude", sa.Float()), schema="discovery")
    op.add_column("region_refreshes", sa.Column("locale", sa.String(16)), schema="discovery")
    op.add_column("region_refreshes", sa.Column("focus", sa.String(24)), schema="discovery")
    op.add_column("region_refreshes", sa.Column("attempt", sa.Integer(), nullable=False, server_default="0"), schema="discovery")
    op.add_column("region_refreshes", sa.Column("expires_at", sa.DateTime(timezone=True)), schema="discovery")
    op.create_index("ix_discovery_refreshes_expiry", "region_refreshes", ["expires_at"], schema="discovery")


def downgrade() -> None:
    op.drop_index("ix_discovery_refreshes_expiry", table_name="region_refreshes", schema="discovery")
    op.drop_column("region_refreshes", "expires_at", schema="discovery")
    op.drop_column("region_refreshes", "attempt", schema="discovery")
    op.drop_column("region_refreshes", "focus", schema="discovery")
    op.drop_column("region_refreshes", "locale", schema="discovery")
    op.drop_column("region_refreshes", "center_longitude", schema="discovery")
    op.drop_column("region_refreshes", "center_latitude", schema="discovery")
    op.drop_column("region_refreshes", "region_id", schema="discovery")
    op.drop_index("ix_discovery_evidence_source_document", table_name="evidence", schema="discovery")
    op.drop_column("evidence", "source_version", schema="discovery")
    op.drop_column("evidence", "source_document_id", schema="discovery")
    op.drop_table("source_documents", schema="discovery")
