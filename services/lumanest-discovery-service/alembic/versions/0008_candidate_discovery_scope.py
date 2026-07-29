"""Separate human-interest discovery candidates from generic POI discovery."""

from alembic import op
import sqlalchemy as sa


revision = "0008_candidate_discovery_scope"
down_revision = "0007_refresh_empty_state"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "places",
        sa.Column(
            "discovery_scope",
            sa.String(16),
            nullable=False,
            server_default="general",
        ),
        schema="discovery",
    )
    op.create_check_constraint(
        "ck_discovery_places_scope",
        "places",
        "discovery_scope IN ('general','humanity')",
        schema="discovery",
    )
    op.create_index(
        "ix_discovery_places_scope_valid",
        "places",
        ["discovery_scope", "published", "valid_until"],
        schema="discovery",
    )


def downgrade() -> None:
    op.drop_index(
        "ix_discovery_places_scope_valid",
        table_name="places",
        schema="discovery",
    )
    op.drop_constraint(
        "ck_discovery_places_scope",
        "places",
        schema="discovery",
        type_="check",
    )
    op.drop_column("places", "discovery_scope", schema="discovery")
