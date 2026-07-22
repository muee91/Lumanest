from __future__ import annotations

import hashlib
import json
import logging
import secrets
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
    PhotographyTarget,
    ShootingTarget,
    ShootingSessionFeedbackRequest,
    ShootingFeedbackCalibrationResponse,
    SourceStatus,
    SpatialFeaturesImport,
    WildlifeLayerArea,
)


logger = logging.getLogger(__name__)


def _log_degraded(operation: str, error: Exception) -> None:
    # Never log query parameters: they may contain the user's current
    # coordinate. Operation and exception class are sufficient for diagnosis.
    logger.warning(
        "context_store_degraded operation=%s error=%s",
        operation,
        type(error).__name__,
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
            except Exception as error:
                _log_degraded("readiness_postgres", error)
                database = False
        if self.redis is not None:
            try:
                cache = bool(await self.redis.ping())
            except Exception as error:
                _log_degraded("readiness_redis", error)
                cache = False
        return {"postgres": database, "redis": cache}

    async def spatial_evidence(self, latitude: float, longitude: float) -> SceneEvidence:
        if self.engine is None:
            return SceneEvidence()
        query = text("""
            SELECT spatial_features.kind, spatial_features.evidence_class, source_registry.category
            FROM spatial_features
            JOIN source_registry ON source_registry.id = spatial_features.source_id
            WHERE spatial_features.enabled = TRUE
              AND source_registry.enabled = TRUE
              AND source_registry.license_status = 'approved'
              AND ST_Intersects(
                spatial_features.geometry,
                ST_Transform(
                    ST_SetSRID(ST_Point(:longitude, :latitude), 4326),
                    ST_SRID(spatial_features.geometry)
                )
              )
            LIMIT 32
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(
                    query, {"latitude": latitude, "longitude": longitude}
                )).all()
        except Exception as error:
            _log_degraded("spatial_evidence", error)
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

    async def wildlife_layers(
        self, latitude: float, longitude: float, radius_km: int
    ) -> list[WildlifeLayerArea]:
        if self.engine is None:
            raise RuntimeError("storage_not_configured")
        query = text("""
            SELECT spatial_features.id,
                   CASE
                       WHEN spatial_features.sensitivity = 'sensitive'
                       THEN '历史观察区域'
                       ELSE spatial_features.name
                   END AS public_name,
                   ST_AsGeoJSON(
                       ST_SimplifyPreserveTopology(spatial_features.geometry, 0.0005),
                       6
                   ) AS geometry,
                   source_registry.attribution,
                   source_registry.version,
                   source_registry.updated_at
            FROM spatial_features
            JOIN source_registry ON source_registry.id = spatial_features.source_id
            WHERE spatial_features.enabled = TRUE
              AND source_registry.enabled = TRUE
              AND source_registry.license_status = 'approved'
              AND source_registry.category = 'wildlifeHistorical'
              AND spatial_features.evidence_class = 'wildlifeOpportunity'
              AND spatial_features.kind = 'protected'
              AND ST_GeometryType(spatial_features.geometry) IN ('ST_Polygon', 'ST_MultiPolygon')
              AND ST_DWithin(
                  spatial_features.geometry::geography,
                  ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography,
                  :radius_meters
              )
            ORDER BY spatial_features.sensitivity DESC, spatial_features.id
            LIMIT 50
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(
                    query,
                    {
                        "latitude": latitude,
                        "longitude": longitude,
                        "radius_meters": radius_km * 1000,
                    },
                )).mappings().all()
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error
        return [
            WildlifeLayerArea.model_validate({
                "id": row["id"],
                "name": row["public_name"],
                "geometry": json.loads(row["geometry"]),
                "source": {
                    "attribution": row["attribution"],
                    "version": row["version"],
                    "updatedAt": row["updated_at"],
                },
            })
            for row in rows
        ]

    async def photography_target(
        self, latitude: float, longitude: float
    ) -> PhotographyTarget | None:
        """Find one reviewed static target near the current *request* point.

        The request location is used only in the SQL predicate and is never
        persisted, returned, or logged.  A target is deliberately absent when
        there is no explicitly imported public Point within the conservative
        radius; ordinary scene geometry must never become a navigation target.
        """
        if self.engine is None:
            return None
        query = text("""
            SELECT spatial_features.id, spatial_features.name,
                   spatial_features.target_type,
                   ST_Y(spatial_features.geometry) AS latitude,
                   ST_X(spatial_features.geometry) AS longitude
            FROM spatial_features
            JOIN source_registry ON source_registry.id = spatial_features.source_id
            WHERE spatial_features.enabled = TRUE
              AND source_registry.enabled = TRUE
              AND source_registry.license_status = 'approved'
              AND spatial_features.sensitivity = 'public'
              AND spatial_features.evidence_class = 'scene'
              AND spatial_features.target_type IN ('viewpoint', 'lakeshore', 'trailhead', 'urban')
              AND ST_GeometryType(spatial_features.geometry) = 'ST_Point'
              AND ST_DWithin(
                  spatial_features.geometry::geography,
                  ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography,
                  25000
              )
            ORDER BY
              ST_Distance(
                  spatial_features.geometry::geography,
                  ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography
              ) ASC,
              spatial_features.id ASC
            LIMIT 1
        """)
        try:
            async with self.engine.connect() as connection:
                row = (await connection.execute(query, {
                    "latitude": latitude, "longitude": longitude,
                })).mappings().first()
        except SQLAlchemyError as error:
            _log_degraded("photography_target", error)
            return None
        if row is None:
            return None
        target_hash = hashlib.sha256(str(row["id"]).encode("utf-8")).hexdigest()[:24]
        return PhotographyTarget.model_validate({
            "id": f"target_{target_hash}",
            "name": row["name"],
            "kind": row["target_type"],
            "coordinate": {
                "latitude": float(row["latitude"]),
                "longitude": float(row["longitude"]),
                "system": "wgs84",
            },
            # This is bound to the opportunity window by the rule layer.
            "arrivalDeadline": datetime.now(timezone.utc),
        })

    async def shooting_targets(
        self,
        latitude: float,
        longitude: float,
        direction_degrees: float,
        session_kind: str,
    ) -> list[ShootingTarget]:
        """Return fully reviewed targets aligned with one session kind."""
        if self.engine is None:
            return []
        query = text("""
            SELECT spatial_features.id, spatial_features.name,
                   ST_Y(spatial_features.geometry) AS latitude,
                   ST_X(spatial_features.geometry) AS longitude,
                   spatial_features.supported_sessions,
                   spatial_features.view_bearing_degrees,
                   spatial_features.bearing_tolerance_degrees,
                   spatial_features.access_modes,
                   spatial_features.lead_time_minutes,
                   spatial_features.arrival_radius_meters,
                   spatial_features.shoreline_side,
                   spatial_features.reviewed_at,
                   spatial_features.review_reference,
                   source_registry.attribution,
                   source_registry.license_id,
                   source_registry.source_url,
                   LEAST(
                       ABS(spatial_features.view_bearing_degrees - :direction),
                       360 - ABS(spatial_features.view_bearing_degrees - :direction)
                   ) AS bearing_delta
            FROM spatial_features
            JOIN source_registry ON source_registry.id = spatial_features.source_id
            WHERE spatial_features.enabled = TRUE
              AND spatial_features.shooting_session_target = TRUE
              AND spatial_features.target_type = 'lakeshore'
              AND spatial_features.sensitivity = 'public'
              AND spatial_features.evidence_class = 'scene'
              AND source_registry.enabled = TRUE
              AND source_registry.license_status = 'approved'
              AND source_registry.license_id IS NOT NULL
              AND source_registry.source_url IS NOT NULL
              AND spatial_features.review_reference IS NOT NULL
              AND spatial_features.shoreline_side IS NOT NULL
              AND ST_GeometryType(spatial_features.geometry) = 'ST_Point'
              AND spatial_features.supported_sessions @>
                  CAST(:supported_sessions AS jsonb)
              AND LEAST(
                  ABS(spatial_features.view_bearing_degrees - :direction),
                  360 - ABS(spatial_features.view_bearing_degrees - :direction)
              ) <= spatial_features.bearing_tolerance_degrees
              AND ST_DWithin(
                  spatial_features.geometry::geography,
                  ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography,
                  50000
              )
            ORDER BY bearing_delta ASC,
                     ST_Distance(
                         spatial_features.geometry::geography,
                         ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography
                     ) ASC,
                     spatial_features.id ASC
            LIMIT 3
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(query, {
                    "latitude": latitude,
                    "longitude": longitude,
                    "direction": direction_degrees,
                    "supported_sessions": f'["{session_kind}"]',
                })).mappings().all()
        except SQLAlchemyError as error:
            _log_degraded("shooting_targets", error)
            return []
        targets: list[ShootingTarget] = []
        for row in rows:
            target_hash = hashlib.sha256(str(row["id"]).encode("utf-8")).hexdigest()[:24]
            targets.append(ShootingTarget.model_validate({
                "id": f"target_{target_hash}",
                "name": row["name"],
                "kind": "lakeshore",
                "coordinate": {
                    "latitude": float(row["latitude"]),
                    "longitude": float(row["longitude"]),
                    "system": "wgs84",
                },
                "supportedSessions": row["supported_sessions"],
                "viewBearingDegrees": row["view_bearing_degrees"],
                "bearingToleranceDegrees": row["bearing_tolerance_degrees"],
                "accessModes": row["access_modes"],
                "leadTimeMinutes": row["lead_time_minutes"],
                "arrivalRadiusMeters": row["arrival_radius_meters"],
                "shorelineSide": row["shoreline_side"],
                "reviewedAt": row["reviewed_at"],
                "reviewReference": row["review_reference"],
                "sourceAttribution": row["attribution"],
                "sourceLicense": row["license_id"],
                "sourceUrl": row["source_url"],
            }))
        return targets

    async def resolve_shooting_target(
        self,
        target_id: str,
        latitude: float,
        longitude: float,
    ) -> ShootingTarget | None:
        """Resolve a reviewed target near its public coordinate and verify its ID.

        The coordinate is the target coordinate already returned to clients,
        not a device or user coordinate. Bounding the lookup prevents a global
        target scan while the opaque identifier prevents database IDs leaking.
        """
        if self.engine is None:
            return None
        query = text("""
            SELECT spatial_features.id, spatial_features.name,
                   ST_Y(spatial_features.geometry) AS latitude,
                   ST_X(spatial_features.geometry) AS longitude,
                   spatial_features.supported_sessions,
                   spatial_features.view_bearing_degrees,
                   spatial_features.bearing_tolerance_degrees,
                   spatial_features.access_modes,
                   spatial_features.lead_time_minutes,
                   spatial_features.arrival_radius_meters,
                   spatial_features.shoreline_side,
                   spatial_features.reviewed_at,
                   spatial_features.review_reference,
                   source_registry.attribution,
                   source_registry.license_id,
                   source_registry.source_url
            FROM spatial_features
            JOIN source_registry ON source_registry.id = spatial_features.source_id
            WHERE spatial_features.enabled = TRUE
              AND spatial_features.shooting_session_target = TRUE
              AND spatial_features.target_type = 'lakeshore'
              AND spatial_features.sensitivity = 'public'
              AND spatial_features.evidence_class = 'scene'
              AND source_registry.enabled = TRUE
              AND source_registry.license_status = 'approved'
              AND source_registry.license_id IS NOT NULL
              AND source_registry.source_url IS NOT NULL
              AND spatial_features.review_reference IS NOT NULL
              AND spatial_features.shoreline_side IS NOT NULL
              AND ST_GeometryType(spatial_features.geometry) = 'ST_Point'
              AND ST_DWithin(
                  spatial_features.geometry::geography,
                  ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography,
                  100
              )
            ORDER BY spatial_features.id ASC
            LIMIT 8
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(query, {
                    "latitude": latitude,
                    "longitude": longitude,
                })).mappings().all()
        except SQLAlchemyError as error:
            _log_degraded("resolve_shooting_target", error)
            return None
        for row in rows:
            public_id = (
                "target_"
                + hashlib.sha256(str(row["id"]).encode("utf-8")).hexdigest()[:24]
            )
            if public_id != target_id:
                continue
            return ShootingTarget.model_validate({
                "id": public_id,
                "name": row["name"],
                "kind": "lakeshore",
                "coordinate": {
                    "latitude": float(row["latitude"]),
                    "longitude": float(row["longitude"]),
                    "system": "wgs84",
                },
                "supportedSessions": row["supported_sessions"],
                "viewBearingDegrees": row["view_bearing_degrees"],
                "bearingToleranceDegrees": row["bearing_tolerance_degrees"],
                "accessModes": row["access_modes"],
                "leadTimeMinutes": row["lead_time_minutes"],
                "arrivalRadiusMeters": row["arrival_radius_meters"],
                "shorelineSide": row["shoreline_side"],
                "reviewedAt": row["reviewed_at"],
                "reviewReference": row["review_reference"],
                "sourceAttribution": row["attribution"],
                "sourceLicense": row["license_id"],
                "sourceUrl": row["source_url"],
            })
        return None

    async def record_shooting_feedback(
        self, body: ShootingSessionFeedbackRequest
    ) -> None:
        """Persist only the anonymous fields allowed by the V1 feedback contract."""
        if self.engine is None:
            raise RuntimeError("storage_not_configured")
        query = text("""
            INSERT INTO shooting_session_feedback (
                id, received_at, rule_version, condition_band, factors,
                outcome, reasons, target_id
            ) VALUES (
                :id, :received_at, :rule_version, :condition_band, CAST(:factors AS jsonb),
                :outcome, CAST(:reasons AS jsonb), :target_id
            )
        """)
        try:
            async with self.engine.begin() as connection:
                await connection.execute(query, {
                    "id": secrets.token_hex(32),
                    "received_at": datetime.now(timezone.utc),
                    "rule_version": body.rule_version,
                    "condition_band": body.condition_band,
                    "factors": json.dumps(
                        [item.model_dump(mode="json") for item in body.factors],
                        separators=(",", ":"),
                    ),
                    "outcome": body.outcome,
                    "reasons": json.dumps(body.reasons, separators=(",", ":")),
                    "target_id": body.target_id,
                })
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error

    async def shooting_feedback_calibration(
        self,
        since: datetime,
        minimum_samples: int,
    ) -> ShootingFeedbackCalibrationResponse:
        """Aggregate anonymous outcomes without exposing rows or target IDs."""
        if self.engine is None:
            raise RuntimeError("storage_not_configured")
        query = text("""
            SELECT shooting_session_feedback.rule_version,
                   shooting_session_feedback.condition_band,
                   factor.value->>'id' AS factor_id,
                   factor.value->>'effect' AS factor_effect,
                   COUNT(*)::int AS evaluated_count,
                   COUNT(*) FILTER (
                       WHERE shooting_session_feedback.outcome = 'captured'
                   )::int AS captured_count,
                   COUNT(*) FILTER (
                       WHERE shooting_session_feedback.outcome = 'conditionsDidNotAppear'
                   )::int AS conditions_did_not_appear_count
            FROM shooting_session_feedback
            CROSS JOIN LATERAL jsonb_array_elements(
                shooting_session_feedback.factors
            ) AS factor(value)
            WHERE shooting_session_feedback.received_at >= :since
              AND shooting_session_feedback.condition_band IS NOT NULL
              AND shooting_session_feedback.outcome IN (
                  'captured', 'conditionsDidNotAppear'
              )
            GROUP BY shooting_session_feedback.rule_version,
                     shooting_session_feedback.condition_band,
                     factor.value->>'id',
                     factor.value->>'effect'
            HAVING COUNT(*) >= :minimum_samples
            ORDER BY shooting_session_feedback.rule_version,
                     shooting_session_feedback.condition_band,
                     factor.value->>'id',
                     factor.value->>'effect'
            LIMIT 500
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (
                    await connection.execute(
                        query,
                        {"since": since, "minimum_samples": minimum_samples},
                    )
                ).mappings().all()
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error
        return ShootingFeedbackCalibrationResponse.model_validate(
            {
                "generatedAt": datetime.now(timezone.utc),
                "since": since,
                "minimumSamples": minimum_samples,
                "rows": [
                    {
                        "ruleVersion": row["rule_version"],
                        "conditionBand": row["condition_band"],
                        "factorId": row["factor_id"],
                        "factorEffect": row["factor_effect"],
                        "evaluatedCount": row["evaluated_count"],
                        "capturedCount": row["captured_count"],
                        "conditionsDidNotAppearCount": row[
                            "conditions_did_not_appear_count"
                        ],
                        "capturedRate": row["captured_count"]
                        / row["evaluated_count"],
                    }
                    for row in rows
                ],
            }
        )

    async def cached_snapshot(self, fingerprint: str) -> dict | None:
        if self.redis is None:
            return None
        try:
            raw = await self.redis.get(f"context:v5:{fingerprint}")
            return json.loads(raw) if raw else None
        except Exception as error:
            _log_degraded("cached_snapshot", error)
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
        except Exception as error:
            _log_degraded("active_astronomy_events", error)
            return []

    async def cache_snapshot(self, fingerprint: str, body: dict) -> None:
        if self.redis is None:
            return
        try:
            await self.redis.setex(f"context:v5:{fingerprint}", 600, json.dumps(body, separators=(",", ":")))
        except Exception as error:
            _log_degraded("cache_snapshot", error)
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
                            id, dataset_type, enabled, license_status, attribution, version, category,
                            license_id, source_url, license_url, updated_at
                        ) VALUES (
                            :id, :dataset_type, :enabled, :license_status, :attribution, :version, :category,
                            :license_id, :source_url, :license_url, :updated_at
                        )
                        ON CONFLICT (id) DO UPDATE SET
                            dataset_type = EXCLUDED.dataset_type,
                            enabled = EXCLUDED.enabled,
                            license_status = EXCLUDED.license_status,
                            attribution = EXCLUDED.attribution,
                            version = EXCLUDED.version,
                            category = EXCLUDED.category,
                            license_id = EXCLUDED.license_id,
                            source_url = EXCLUDED.source_url,
                            license_url = EXCLUDED.license_url,
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
                        "license_id": body.source.license_id,
                        "source_url": str(body.source.source_url) if body.source.source_url else None,
                        "license_url": str(body.source.license_url) if body.source.license_url else None,
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
                                    id, external_id, source_id, kind, name, sensitivity, evidence_class, target_type,
                                    shooting_session_target, supported_sessions, view_bearing_degrees,
                                    bearing_tolerance_degrees, access_modes, lead_time_minutes,
                                    arrival_radius_meters, shoreline_side, reviewed_at, review_reference,
                                    enabled, geometry
                                ) VALUES (
                                    :id, :external_id, :source_id, :kind, :name, :sensitivity, :evidence_class, :target_type,
                                    :shooting_session_target, CAST(:supported_sessions AS jsonb), :view_bearing_degrees,
                                    :bearing_tolerance_degrees, CAST(:access_modes AS jsonb), :lead_time_minutes,
                                    :arrival_radius_meters, :shoreline_side, :reviewed_at, :review_reference,
                                    :enabled,
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
                                "target_type": feature.properties.target_type,
                                "shooting_session_target": feature.properties.shooting_session_target,
                                "supported_sessions": json.dumps(feature.properties.supported_sessions),
                                "view_bearing_degrees": feature.properties.view_bearing_degrees,
                                "bearing_tolerance_degrees": feature.properties.bearing_tolerance_degrees,
                                "access_modes": json.dumps(feature.properties.access_modes),
                                "lead_time_minutes": feature.properties.lead_time_minutes,
                                "arrival_radius_meters": feature.properties.arrival_radius_meters,
                                "shoreline_side": feature.properties.shoreline_side,
                                "reviewed_at": feature.properties.reviewed_at,
                                "review_reference": str(feature.properties.review_reference)
                                if feature.properties.review_reference else None,
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
            keys = [key async for key in self.redis.scan_iter(match="context:v5:*")]
            if keys:
                await self.redis.delete(*keys)
            return True
        except Exception as error:
            _log_degraded("invalidate_snapshot_cache", error)
            return False

    async def source_statuses(self) -> list[SourceStatus]:
        updated_at = None
        if self.redis is not None:
            try:
                raw = await self.redis.get("source:qweather:last-updated")
                updated_at = datetime.fromisoformat(raw.replace("Z", "+00:00")) if raw else None
            except Exception as error:
                _log_degraded("source_status_weather_revision", error)
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
                ("qweather-air-quality", True, "approved"),
            )
        ]
        if self.engine is None:
            return builtins
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(text("""
                    SELECT id, dataset_type, enabled, license_status, attribution, version,
                           license_id, source_url, license_url, updated_at
                    FROM source_registry ORDER BY id
                """))).mappings().all()
            return builtins + [SourceStatus.model_validate(dict(row)) for row in rows]
        except Exception as error:
            _log_degraded("source_status_registry", error)
            return builtins
