"""Allow refresh jobs to record successful completion."""

from alembic import op


revision = "0006_refresh_terminal_states"
down_revision = "0005_region_insights"
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
        "state IN ('pending','attempted','completed','failed')",
        schema="discovery",
    )


def downgrade() -> None:
    op.execute("UPDATE discovery.region_refreshes SET state = 'attempted' WHERE state = 'completed'")
    op.drop_constraint(
        "ck_discovery_refresh_state",
        "region_refreshes",
        schema="discovery",
        type_="check",
    )
    op.create_check_constraint(
        "ck_discovery_refresh_state",
        "region_refreshes",
        "state IN ('pending','attempted','failed')",
        schema="discovery",
    )
