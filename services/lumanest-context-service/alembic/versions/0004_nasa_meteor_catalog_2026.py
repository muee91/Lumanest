"""Install the reviewed NASA 2026 meteor-shower windows."""

from hashlib import sha256

from alembic import op
import sqlalchemy as sa


revision = "0004_nasa_meteor_catalog_2026"
down_revision = "0003_wildlife_evidence_classes"
branch_labels = None
depends_on = None


source_id = "nasa-meteor-showers-2026"
events = (
    (
        "perseids-2026-window",
        "2026-08-12T12:00:00+00:00",
        "2026-08-13T12:00:00+00:00",
        "英仙座流星雨年度活跃窗口",
        "https://science.nasa.gov/solar-system/meteors-meteorites/perseids/",
    ),
    (
        "orionids-2026-window",
        "2026-10-21T12:00:00+00:00",
        "2026-10-22T12:00:00+00:00",
        "猎户座流星雨年度活跃窗口",
        "https://science.nasa.gov/solar-system/meteors-meteorites/orionids/",
    ),
    (
        "leonids-2026-window",
        "2026-11-17T12:00:00+00:00",
        "2026-11-18T12:00:00+00:00",
        "狮子座流星雨年度活跃窗口",
        "https://science.nasa.gov/solar-system/meteors-meteorites/leonids/",
    ),
    (
        "geminids-2026-window",
        "2026-12-13T12:00:00+00:00",
        "2026-12-14T12:00:00+00:00",
        "双子座流星雨年度活跃窗口",
        "https://science.nasa.gov/solar-system/meteors-meteorites/geminids/",
    ),
)


def upgrade() -> None:
    connection = op.get_bind()
    connection.execute(
        sa.text("""
            INSERT INTO source_registry (
                id, enabled, license_status, attribution, updated_at,
                dataset_type, version, category
            ) VALUES (
                :id, TRUE, 'approved', :attribution, :updated_at,
                'astronomyEvents', '2026.07-reviewed', 'spatial'
            )
            ON CONFLICT (id) DO UPDATE SET
                enabled = EXCLUDED.enabled,
                license_status = EXCLUDED.license_status,
                attribution = EXCLUDED.attribution,
                updated_at = EXCLUDED.updated_at,
                dataset_type = EXCLUDED.dataset_type,
                version = EXCLUDED.version
        """),
        {
            "id": source_id,
            "attribution": "NASA Science meteor shower guides; reviewed by LumaNest 2026-07-16",
            "updated_at": "2026-07-16T00:00:00+00:00",
        },
    )
    for external_id, starts_at, ends_at, title, source_url in events:
        record_id = sha256(f"astronomy\0{source_id}\0{external_id}".encode()).hexdigest()
        connection.execute(
            sa.text("""
                INSERT INTO astronomy_events (
                    id, external_id, source_id, event_type, starts_at, ends_at,
                    title, source_url, enabled
                ) VALUES (
                    :id, :external_id, :source_id, 'meteorShower', :starts_at, :ends_at,
                    :title, :source_url, TRUE
                )
                ON CONFLICT (id) DO UPDATE SET
                    starts_at = EXCLUDED.starts_at,
                    ends_at = EXCLUDED.ends_at,
                    title = EXCLUDED.title,
                    source_url = EXCLUDED.source_url,
                    enabled = EXCLUDED.enabled
            """),
            {
                "id": record_id,
                "external_id": external_id,
                "source_id": source_id,
                "starts_at": starts_at,
                "ends_at": ends_at,
                "title": title,
                "source_url": source_url,
            },
        )


def downgrade() -> None:
    connection = op.get_bind()
    connection.execute(
        sa.text("DELETE FROM astronomy_events WHERE source_id = :source_id"),
        {"source_id": source_id},
    )
    connection.execute(
        sa.text("DELETE FROM source_registry WHERE id = :source_id"),
        {"source_id": source_id},
    )
