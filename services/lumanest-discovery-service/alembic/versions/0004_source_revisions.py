"""Add immutable crawled document revisions and bounded evidence windows."""

from alembic import op
import sqlalchemy as sa


revision = "0004_source_revisions"
down_revision = "0003_freshness_focus"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "source_document_revisions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("source_document_id", sa.String(64), sa.ForeignKey("discovery.source_documents.id", ondelete="CASCADE"), nullable=False),
        sa.Column("content_hash", sa.String(64), nullable=False),
        sa.Column("requested_url", sa.String(1000), nullable=False),
        sa.Column("final_url", sa.String(1000), nullable=False),
        sa.Column("title", sa.String(300)),
        sa.Column("language", sa.String(16)),
        sa.Column("published_at", sa.DateTime(timezone=True)),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("http_status", sa.Integer()),
        sa.Column("crawl_status", sa.String(24), nullable=False),
        sa.Column("crawler_name", sa.String(32), nullable=False, server_default="crawl4ai"),
        sa.Column("crawler_version", sa.String(32), nullable=False),
        sa.Column("policy_version", sa.String(80), nullable=False),
        sa.Column("cleaned_markdown", sa.Text()),
        sa.Column("markdown_bytes", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_code", sa.String(80)),
        sa.UniqueConstraint("source_document_id", "content_hash", name="uq_discovery_revision_hash"),
        schema="discovery",
    )
    op.create_table(
        "evidence_windows",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("revision_id", sa.String(64), sa.ForeignKey("discovery.source_document_revisions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ordinal", sa.SmallInteger(), nullable=False),
        sa.Column("text", sa.String(1200), nullable=False),
        sa.Column("locator", sa.String(300), nullable=False),
        sa.Column("relevance_score", sa.Float(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("revision_id", "ordinal", name="uq_discovery_window_ordinal"),
        schema="discovery",
    )


def downgrade() -> None:
    op.drop_table("evidence_windows", schema="discovery")
    op.drop_table("source_document_revisions", schema="discovery")
