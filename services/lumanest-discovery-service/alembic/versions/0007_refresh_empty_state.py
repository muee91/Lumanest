"""Record successful discovery refreshes that found no reviewed evidence."""

from alembic import op


revision = "0007_refresh_empty_state"
down_revision = "0006_refresh_terminal_states"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint(
        "ck_discovery_refresh_state",
        "region_refreshes",
        schema="discovery",
        type_="check",
    )
    op.create_check_constraint(
        "ck_discovery_refresh_state",
        "region_refreshes",
        "state IN ('pending','attempted','completed','empty','failed')",
        schema="discovery",
    )


def downgrade() -> None:
    op.execute("UPDATE discovery.region_refreshes SET state = 'completed' WHERE state = 'empty'")
    op.drop_constraint(
        "ck_discovery_refresh_state",
        "region_refreshes",
        schema="discovery",
        type_="check",
    )
    op.create_check_constraint(
        "ck_discovery_refresh_state",
        "region_refreshes",
        "state IN ('pending','attempted','completed','failed')",
        schema="discovery",
    )
