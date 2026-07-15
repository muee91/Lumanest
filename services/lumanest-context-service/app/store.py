from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone

from redis.asyncio import Redis
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from .models import (
    AstronomyEventsImport,
    ContextImportRequest,
    ContextImportResult,
    SceneEvidence,
    SourceStatus,
    SpatialFeaturesImport,
)


class ContextStore:
    def __init__(self, database_url: str | None, redis_url: str | None) -> None:
        self.engine: AsyncEngine | None = create_async_engine(database_url) if database_url else None
        self.redis: Redis | None = Redis.from_url(redis_url, decode_responses=True) if redis_url else None

    async def close(self) -> None:
        if self.redis is not None:
            await self.redis.aclose()
        if self.engine is not None:
            await self.engine.dispose()

    async def readiness(self) -> dict[str, bool]:
        database = False
        cache = False
        if self.engine is not None:
            try:
                async with self.engine.connect() as connection:
                    database = (await connection.execute(text("SELECT 1"))).scalar_one() == 1
            except Exception:
                database = False
        if self.redis is not None:
            try:
                cache = bool(await self.redis.ping())
            except Exception:
                cache = False
        return {"postgres": database, "redis": cache}

    async def spatial_evidence(self, latitude: float, longitude: float) -> SceneEvidence:
        if self.engine is None:
            return SceneEvidence()
        query = text("""
            SELECT spatial_features.kind, spatial_features.evidence_class, source_registry.category
            FROM spatial_features
            JOIN source_registry ON source_registry.id = spatial_features.source_id
            WHERE enabled = TRUE
              AND source_registry.enabled = TRUE
              AND source_registry.license_status = 'approved'
              AND ST_Intersects(
                geometry,
                ST_Transform(ST_SetSRID(ST_Point(:longitude, :latitude), 4326), ST_SRID(geometry))
              )
            LIMIT 32
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(
                    query, {"latitude": latitude, "longitude": longitude}
                )).scalars().all()
        except Exception:
            return SceneEvidence()
        kinds = {row[0] for row in rows}
        evidence = {(row[1], row[2]) for row in rows}
        return SceneEvidence(
            urban="urban" in kinds,
            waterBody="water" in kinds,
            mountainous="mountain" in kinds,
            aridLand="arid" in kinds,
            settlement="settlement" in kinds,
            wildlifeOpportunity=("wildlifeOpportunity", "wildlifeHistorical") in evidence,
            wildlifeSafety=("wildlifeSafety", "officialRisk") in evidence,
        )

    async def cached_snapshot(self, fingerprint: str) -> dict | None:
        if self.redis is None:
            return None
        try:
            raw = await self.redis.get(f"context:v2:{fingerprint}")
            return json.loads(raw) if raw else None
        except Exception:
            return None

    async def active_astronomy_events(self, moment: datetime) -> list[dict]:
        """Return only currently active events from approved, enabled sources."""
        if self.engine is None:
            return []
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(text("""
                    SELECT astronomy_events.external_id, astronomy_events.event_type,
                           astronomy_events.title, astronomy_events.source_url,
                           astronomy_events.starts_at, astronomy_events.ends_at
                    FROM astronomy_events
                    JOIN source_registry ON source_registry.id = astronomy_events.source_id
                    WHERE astronomy_events.enabled = TRUE
                      AND source_registry.enabled = TRUE
                      AND source_registry.license_status = 'approved'
                      AND astronomy_events.starts_at <= :moment
                      AND astronomy_events.ends_at > :moment
                    ORDER BY astronomy_events.starts_at ASC
                    LIMIT 3
                """), {"moment": moment})).mappings().all()
            return [dict(row) for row in rows]
        except Exception:
            return []

    async def cache_snapshot(self, fingerprint: str, body: dict) -> None:
        if self.redis is None:
            return
        try:
            await self.redis.setex(f"context:v2:{fingerprint}", 900, json.dumps(body, separators=(",", ":")))
        except Exception:
            return

    async def import_dataset(self, body: ContextImportRequest) -> ContextImportResult:
        if self.engine is None:
            raise RuntimeError("storage_not_configured")

        imported_count = 0
        try:
            async with self.engine.begin() as connection:
                await connection.execute(
                    text("""
                        INSERT INTO source_registry (
                            id, dataset_type, enabled, license_status, attribution, version, category, updated_at
                        ) VALUES (
                            :id, :dataset_type, :enabled, :license_status, :attribution, :version, :category, :updated_at
                        )
                        ON CONFLICT (id) DO UPDATE SET
                            dataset_type = EXCLUDED.dataset_type,
                            enabled = EXCLUDED.enabled,
                            license_status = EXCLUDED.license_status,
                            attribution = EXCLUDED.attribution,
                            version = EXCLUDED.version,
                            category = EXCLUDED.category,
                            updated_at = EXCLUDED.updated_at
                    """),
                    {
                        "id": body.source.id,
                        "dataset_type": body.dataset_type,
                        "enabled": body.source.enabled,
                        "license_status": body.source.license_status,
                        "attribution": body.source.attribution,
                        "version": body.source.version,
                        "category": body.source.category,
                        "updated_at": datetime.now(timezone.utc),
                    },
                )
                await connection.execute(
                    text("DELETE FROM spatial_features WHERE source_id = :source_id"),
                    {"source_id": body.source.id},
                )
                await connection.execute(
                    text("DELETE FROM astronomy_events WHERE source_id = :source_id"),
                    {"source_id": body.source.id},
                )
                if isinstance(body, SpatialFeaturesImport):
                    for feature in body.feature_collection.features:
                        record_id = hashlib.sha256(
                            f"spatial\0{body.source.id}\0{feature.id}".encode("utf-8")
                        ).hexdigest()
                        geometry = json.dumps(
                            feature.geometry.model_dump(mode="json"), separators=(",", ":")
                        )
                        valid = (
                            await connection.execute(
                                text("""
                                    SELECT ST_IsValid(
                                        ST_SetSRID(ST_GeomFromGeoJSON(:geometry), 4326)
                                    )
                                """),
                                {"geometry": geometry},
                            )
                        ).scalar_one()
                        if not valid:
                            raise ValueError("invalid_geometry")
                        await connection.execute(
                            text("""
                                INSERT INTO spatial_features (
                                    id, external_id, source_id, kind, name, sensitivity, evidence_class, enabled,
                                    geometry
                                ) VALUES (
                                    :id, :external_id, :source_id, :kind, :name, :sensitivity, :evidence_class, :enabled,
                                    ST_SetSRID(ST_GeomFromGeoJSON(:geometry), 4326)
                                )
                            """),
                            {
                                "id": record_id,
                                "external_id": feature.id,
                                "source_id": body.source.id,
                                "kind": feature.properties.kind,
                                "name": feature.properties.name,
                                "sensitivity": feature.properties.sensitivity,
                                "evidence_class": feature.properties.evidence_class,
                                "enabled": body.source.enabled,
                                "geometry": geometry,
                            },
                        )
                    imported_count = len(body.feature_collection.features)
                elif isinstance(body, AstronomyEventsImport):
                    for event in body.events:
                        record_id = hashlib.sha256(
                            f"astronomy\0{body.source.id}\0{event.id}".encode("utf-8")
                        ).hexdigest()
                        await connection.execute(
                            text("""
                                INSERT INTO astronomy_events (
                                    id, external_id, source_id, event_type, starts_at, ends_at,
                                    title, source_url, enabled
                                ) VALUES (
                                    :id, :external_id, :source_id, :event_type, :starts_at, :ends_at,
                                    :title, :source_url, :enabled
                                )
                            """),
                            {
                                "id": record_id,
                                "external_id": event.id,
                                "source_id": body.source.id,
                                "event_type": event.event_type,
                                "starts_at": event.starts_at,
                                "ends_at": event.ends_at,
                                "title": event.title,
                                "source_url": str(event.source_url),
                                "enabled": body.source.enabled,
                            },
                        )
                    imported_count = len(body.events)
        except (ValueError, SQLAlchemyError):
            raise

        cache_invalidated = await self.invalidate_snapshot_cache()
        return ContextImportResult.model_validate(
            {
                "sourceId": body.source.id,
                "datasetType": body.dataset_type,
                "importedCount": imported_count,
                "enabled": body.source.enabled,
                "cacheInvalidated": cache_invalidated,
            }
        )

    async def invalidate_snapshot_cache(self) -> bool:
        if self.redis is None:
            return False
        try:
            keys = [key async for key in self.redis.scan_iter(match="context:v2:*")]
            if keys:
                await self.redis.delete(*keys)
            return True
        except Exception:
            return False

    async def source_statuses(self) -> list[SourceStatus]:
        updated_at = None
        if self.redis is not None:
            try:
                raw = await self.redis.get("source:qweather:last-updated")
                updated_at = datetime.fromisoformat(raw.replace("Z", "+00:00")) if raw else None
            except Exception:
                updated_at = None
        builtins = [
            SourceStatus.model_validate({
                "id": source_id,
                "datasetType": "unknown",
                "enabled": enabled,
                "licenseStatus": license_status,
                "attribution": "QWeather",
                "version": "v7",
                "updatedAt": updated_at if enabled else None,
            })
            for source_id, enabled, license_status in (
                ("qweather-current", True, "approved"),
                ("qweather-hourly", True, "approved"),
                ("qweather-minutely", True, "approved"),
                ("qweather-warning", True, "approved"),
                ("qweather-air-quality", False, "pending"),
            )
        ]
        if self.engine is None:
            return builtins
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(text("""
                    SELECT id, dataset_type, enabled, license_status, attribution, version, updated_at
                    FROM source_registry ORDER BY id
                """))).mappings().all()
            return builtins + [SourceStatus.model_validate(dict(row)) for row in rows]
        except Exception:
            return builtins
