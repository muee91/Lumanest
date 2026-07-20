from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Iterable

from redis.asyncio import Redis
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from .models import (
    BrokerSearchResult,
    DiscoveryActivationType,
    DiscoveryItem,
    DiscoveryRequest,
    DiscoveryResponse,
    ExtractedCandidate,
)


PENDING_SECONDS = 1800
REFRESH_STREAM = "discovery:refresh:stream"
REFRESH_GROUP = "discovery-workers"
REGION_GRID_DEGREES = 0.05
@dataclass(frozen=True)
class FreshnessRule:
    valid_seconds: int
    refresh_seconds: int


FRESHNESS_POLICY: dict[str, FreshnessRule] = {
    "routeConditions": FreshnessRule(15 * 60, 5 * 60),
    "openingAndClosure": FreshnessRule(4 * 60 * 60, 60 * 60),
    "humanityEvents": FreshnessRule(12 * 60 * 60, 2 * 60 * 60),
    "popularPlaces": FreshnessRule(24 * 60 * 60, 24 * 60 * 60),
    "hiddenPlaces": FreshnessRule(3 * 24 * 60 * 60, 3 * 24 * 60 * 60),
    "seasonalSignals": FreshnessRule(24 * 60 * 60, 24 * 60 * 60),
    "localStories": FreshnessRule(30 * 24 * 60 * 60, 30 * 24 * 60 * 60),
}


def response_cache_seconds(mission_type: str) -> int:
    """Keep response cache aligned with the mission's refresh cadence.

    The durable place records have their own validity window. This cache is
    only the fast path and must expire when the next background verification is
    due, rather than forcing every app reopen through the database after ten
    minutes.
    """
    return FRESHNESS_POLICY[mission_type].refresh_seconds


def freshness_until(
    mission_type: str,
    ends_at: datetime | None,
    *,
    now: datetime | None = None,
) -> datetime:
    """Return the signal expiry for the single current mission policy."""
    current = now or datetime.now(timezone.utc)
    if current.tzinfo is None:
        current = current.replace(tzinfo=timezone.utc)
    if mission_type == "humanityEvents" and ends_at is not None:
        return ends_at
    return current + timedelta(seconds=FRESHNESS_POLICY[mission_type].valid_seconds)


@dataclass(frozen=True)
class RegionReference:
    """A short lived, coarse region reference; never a client location."""

    region_id: str
    latitude: float
    longitude: float
    locale: str
    mission_type: str
    focus: str
    radius_meters: int


@dataclass(frozen=True)
class RefreshJob:
    fingerprint: str
    region: RegionReference
    expires_at: int
    attempt: int
    activation_type: DiscoveryActivationType
    dedupe_key: str

    def stream_values(self) -> dict[str, str]:
        return {
            "fingerprint": self.fingerprint,
            "regionId": self.region.region_id,
            "latitude": f"{self.region.latitude:.3f}",
            "longitude": f"{self.region.longitude:.3f}",
            "locale": self.region.locale,
            "missionType": self.region.mission_type,
            "focus": self.region.focus,
            "radiusMeters": str(self.region.radius_meters),
            "expiresAt": str(self.expires_at),
            "attempt": str(self.attempt),
            "activationType": self.activation_type,
            "dedupeKey": self.dedupe_key,
        }


class DiscoveryStore:
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

    @staticmethod
    def region_reference(request: DiscoveryRequest) -> RegionReference:
        """Return a fixed roughly-5 km grid centre rather than the input point."""
        latitude_cell = math.floor(request.region.latitude / REGION_GRID_DEGREES)
        longitude_cell = math.floor(request.region.longitude / REGION_GRID_DEGREES)
        latitude = round((latitude_cell + 0.5) * REGION_GRID_DEGREES, 3)
        longitude = round((longitude_cell + 0.5) * REGION_GRID_DEGREES, 3)
        region_id = f"g{latitude_cell}:{longitude_cell}"
        return RegionReference(
            region_id=region_id,
            latitude=latitude,
            longitude=longitude,
            locale=request.locale.lower(),
            mission_type=request.mission_type,
            focus=request.focus,
            radius_meters=request.region.radius_meters,
        )

    @classmethod
    def fingerprint(cls, request: DiscoveryRequest) -> str:
        region = cls.region_reference(request)
        refresh_seconds = response_cache_seconds(request.mission_type)
        payload = {
            "regionId": region.region_id,
            "locale": region.locale,
            "missionType": region.mission_type,
            "focus": region.focus,
            "radiusMeters": region.radius_meters,
            # The result set is bounded by persisted item validity. A full
            # timestamp here made logically identical foreground requests miss
            # cache every time the app reopened. Retain a mission refresh
            # bucket instead, matching the stale-while-revalidate policy.
            "timeBucket": int(request.time_range.starts_at.timestamp()) // refresh_seconds,
            "routeId": request.route_corridor.route_id if request.route_corridor else None,
            "interests": sorted(request.interests),
            "sourcePolicies": sorted((policy.id, policy.version) for policy in request.source_policies),
            "activationType": request.activation_type,
        }
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

    @classmethod
    def dedupe_key(cls, request: DiscoveryRequest) -> str:
        """Single-flight key: coarse region, mission, time bucket and policy set."""
        region = cls.region_reference(request)
        bucket_seconds = FRESHNESS_POLICY[request.mission_type].refresh_seconds
        bucket = int(request.time_range.starts_at.timestamp()) // bucket_seconds
        payload = {
            "regionId": region.region_id,
            "missionType": request.mission_type,
            "timeBucket": bucket,
            "sourcePolicies": sorted((policy.id, policy.version) for policy in request.source_policies),
        }
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(encoded.encode("utf-8")).hexdigest()

    async def cached(self, fingerprint: str) -> DiscoveryResponse | None:
        if self.redis is None:
            return None
        try:
            raw = await self.redis.get(f"discovery:response:{fingerprint}")
            return DiscoveryResponse.model_validate_json(raw) if raw else None
        except Exception:
            return None

    async def cache(self, fingerprint: str, response: DiscoveryResponse) -> None:
        if self.redis is None:
            return
        try:
            await self.redis.setex(
                f"discovery:response:{fingerprint}",
                response_cache_seconds(response.mission_type),
                response.model_dump_json(by_alias=True),
            )
        except Exception:
            return

    async def refresh_state(self, request: DiscoveryRequest) -> str | None:
        if self.redis is None:
            return None
        try:
            return await self.redis.get(f"discovery:refresh:{self.dedupe_key(request)}")
        except Exception:
            return None

    async def schedule_refresh(self, request: DiscoveryRequest) -> bool:
        """Queue a deduplicated, expiring coarse region job, never a raw point."""
        if self.redis is None:
            return False
        fingerprint = self.fingerprint(request)
        dedupe_key = self.dedupe_key(request)
        region = self.region_reference(request)
        job = RefreshJob(
            fingerprint=fingerprint,
            region=region,
            expires_at=int(datetime.now(timezone.utc).timestamp()) + PENDING_SECONDS,
            attempt=0,
            activation_type=request.activation_type,
            dedupe_key=dedupe_key,
        )
        key = f"discovery:refresh:{dedupe_key}"
        cooldown_key = f"discovery:cooldown:{dedupe_key}"
        try:
            if request.activation_type == "foreground_opportunistic":
                if await self.redis.get(cooldown_key):
                    return False
            if not await self.redis.set(key, "pending", ex=PENDING_SECONDS, nx=True):
                return False
            try:
                await self.redis.xadd(REFRESH_STREAM, job.stream_values(), maxlen=10_000, approximate=True)
                await self.redis.set(
                    cooldown_key,
                    "queued",
                    ex=FRESHNESS_POLICY[request.mission_type].refresh_seconds,
                )
            except Exception:
                # Do not leave callers retrying a task that was never queued.
                if await self.redis.get(key) == "pending":
                    await self.redis.delete(key)
                await self.redis.delete(cooldown_key)
                return False
            return True
        except Exception:
            return False

    async def candidates(self, request: DiscoveryRequest) -> list[DiscoveryItem]:
        if self.engine is None:
            raise RuntimeError("storage_not_configured")
        active_sources = {(policy.id, policy.version) for policy in request.source_policies}
        if request.mission_type == "routeConditions":
            active_sources.add(("amap-traffic", "amap-web-service-v1"))
        elif request.mission_type == "openingAndClosure":
            active_sources.add(("amap-poi", "amap-web-service-v1"))
        # A disabled or removed policy revokes its prior search-derived records
        # immediately, without waiting for their candidate expiry.
        if not active_sources:
            return []
        kind_filter = {
            "popularPlaces": ("candidate_viewpoint", "attraction"),
            "hiddenPlaces": ("candidate_viewpoint", "attraction"),
            "humanityEvents": ("event",),
            "localStories": ("attraction",),
            "routeConditions": ("candidate_viewpoint",),
            "openingAndClosure": ("attraction",),
            "seasonalSignals": ("attraction", "event"),
        }[request.mission_type]
        query = text("""
            SELECT places.id, places.kind, LEFT(places.name, 120) AS name,
                   LEFT(places.summary, 280) AS summary, places.verification,
                   ST_Y(places.geometry) AS latitude, ST_X(places.geometry) AS longitude,
                   ROUND(ST_Distance(
                       places.geometry::geography,
                       ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography
                   ))::integer AS distance_meters,
                   LEFT(places.address, 200) AS address, places.starts_at, places.ends_at,
                   evidence.provider, LEFT(evidence.title, 200) AS evidence_title, evidence.source_url,
                   evidence.retrieved_at, source_document.source_id, source_document.source_version
            FROM discovery.places AS places
            JOIN LATERAL (
                SELECT evidence.provider, evidence.title, evidence.source_url, evidence.retrieved_at,
                       source_document.source_id, source_document.source_version
                FROM discovery.evidence AS evidence
                JOIN discovery.source_documents AS source_document
                  ON source_document.id = evidence.source_document_id
                WHERE evidence.place_id = places.id
                  AND evidence.review_status = 'approved'
                  AND evidence.title IS NOT NULL
                  AND evidence.title <> ''
                ORDER BY retrieved_at DESC
                LIMIT 4
            ) AS evidence ON TRUE
            WHERE places.published = TRUE
              AND places.kind = ANY(CAST(:kinds AS text[]))
              AND (places.valid_until IS NULL OR places.valid_until > NOW())
              AND ST_DWithin(
                    places.geometry::geography,
                    ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography,
                    :radius_meters
              )
            ORDER BY distance_meters ASC, places.updated_at DESC
            LIMIT 80
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(
                    query,
                    {
                        "latitude": request.region.latitude,
                        "longitude": request.region.longitude,
                        "radius_meters": request.region.radius_meters,
                        "kinds": list(kind_filter),
                    },
                )).mappings().all()
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error

        grouped: dict[str, dict] = {}
        for row in rows:
            if (row["source_id"], row["source_version"]) not in active_sources:
                continue
            record = grouped.setdefault(str(row["id"]), {
                "id": row["id"],
                "kind": row["kind"],
                "title": row["name"],
                "subtitle": row["summary"],
                "placeStatus": row["verification"],
                "coordinate": {"latitude": row["latitude"], "longitude": row["longitude"], "system": "wgs84"},
                "distanceMeters": row["distance_meters"],
                "address": row["address"],
                "startsAt": row["starts_at"],
                "endsAt": row["ends_at"],
                "evidence": [],
            })
            record["evidence"].append({
                "publisher": row["provider"],
                "title": row["evidence_title"],
                "url": row["source_url"],
                "observedAt": row["retrieved_at"],
            })
        return [DiscoveryItem.model_validate(item) for item in list(grouped.values())[:40]]

    async def response_for(self, request: DiscoveryRequest) -> tuple[DiscoveryResponse, int]:
        fingerprint = self.fingerprint(request)
        cached = await self.cached(fingerprint)
        if cached is not None:
            return cached, 200

        refresh_state = await self.refresh_state(request)
        now = datetime.now(timezone.utc)
        if refresh_state == "pending":
            return DiscoveryResponse(
                missionType=request.mission_type,
                status="pending",
                generatedAt=now,
                expiresAt=None,
                retryAfterSeconds=30,
                items=[],
            ), 202

        items = await self.candidates(request)
        cache_seconds = response_cache_seconds(request.mission_type)
        response = DiscoveryResponse(
            missionType=request.mission_type,
            status="ready" if items else "refreshing",
            generatedAt=now,
            expiresAt=now + timedelta(seconds=cache_seconds) if items else None,
            retryAfterSeconds=None if items else 30,
            items=items,
        )
        if items:
            await self.cache(fingerprint, response)
        # Existing candidate records are returned immediately, while a
        # deduplicated worker run refreshes them for the next open. This is
        # stale-while-revalidate, not a user-visible loading dependency.
        if request.source_policies:
            await self.schedule_refresh(request)
        return response, 200

    async def record_refresh(self, job: RefreshJob, state: str) -> None:
        """Keep only the coarse, expiry-bound region work reference in PostGIS."""
        if self.engine is None:
            return
        statement = text("""
            INSERT INTO discovery.region_refreshes
                (fingerprint, region_id, center_latitude, center_longitude, locale, focus,
                 state, attempt, requested_at, updated_at, expires_at)
            VALUES
                (:fingerprint, :region_id, :latitude, :longitude, :locale, :focus,
                 :state, :attempt, NOW(), NOW(), to_timestamp(:expires_at))
            ON CONFLICT (fingerprint) DO UPDATE SET
                state = EXCLUDED.state,
                attempt = EXCLUDED.attempt,
                updated_at = NOW(),
                expires_at = EXCLUDED.expires_at
        """)
        try:
            async with self.engine.begin() as connection:
                await connection.execute(text("DELETE FROM discovery.region_refreshes WHERE expires_at <= NOW()"))
                await connection.execute(statement, {
                    "fingerprint": job.fingerprint,
                    "region_id": job.region.region_id,
                    "latitude": job.region.latitude,
                    "longitude": job.region.longitude,
                    "locale": job.region.locale,
                    "focus": job.region.focus,
                    "state": state,
                    "attempt": job.attempt,
                    "expires_at": job.expires_at,
                })
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error

    async def persist_candidates(
        self,
        job: RefreshJob,
        candidates: Iterable[tuple[ExtractedCandidate, list[BrokerSearchResult]]],
    ) -> int:
        """Persist only already-admitted candidate records with source documents.

        The database never receives a model assertion without its source URL.  All
        auto-published records retain `candidate` verification; they are neither
        verified locations nor popularity assertions.
        """
        if self.engine is None:
            raise RuntimeError("storage_not_configured")
        admitted = list(candidates)
        if not admitted:
            return 0
        source_sql = text("""
            INSERT INTO discovery.source_documents
                (id, source_id, source_version, source_url, title, snippet, publisher, published_at, retrieved_at)
            VALUES
                (:id, :source_id, :source_version, :url, :title, :snippet, :publisher, :published_at, NOW())
            ON CONFLICT (source_url) DO UPDATE SET
                source_id = EXCLUDED.source_id, source_version = EXCLUDED.source_version,
                title = EXCLUDED.title, snippet = EXCLUDED.snippet,
                publisher = EXCLUDED.publisher, published_at = EXCLUDED.published_at,
                retrieved_at = NOW()
        """)
        place_sql = text("""
            INSERT INTO discovery.places
                (id, canonical_key, kind, name, summary, verification, published, valid_until,
                 starts_at, ends_at, updated_at, geometry)
            VALUES
                (:id, :canonical_key, :kind, :name, :summary, 'candidate', TRUE,
                 :valid_until, :starts_at, :ends_at, NOW(),
                 ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326))
            ON CONFLICT (canonical_key) DO UPDATE SET
                name = EXCLUDED.name, summary = EXCLUDED.summary, published = TRUE,
                verification = 'candidate', valid_until = EXCLUDED.valid_until,
                starts_at = EXCLUDED.starts_at, ends_at = EXCLUDED.ends_at, updated_at = NOW(),
                geometry = EXCLUDED.geometry
        """)
        evidence_sql = text("""
            INSERT INTO discovery.evidence
                (id, place_id, source_document_id, provider, title, source_url, license, source_version,
                 review_status, retrieved_at, published_at)
            VALUES
                (:id, :place_id, :source_document_id, :provider, :title, :url, :license, :source_version,
                 'approved', NOW(), :published_at)
            ON CONFLICT (id) DO UPDATE SET
                source_document_id = EXCLUDED.source_document_id, provider = EXCLUDED.provider,
                title = EXCLUDED.title, license = EXCLUDED.license,
                source_version = EXCLUDED.source_version, retrieved_at = NOW(), published_at = EXCLUDED.published_at,
                review_status = 'approved'
        """)
        try:
            async with self.engine.begin() as connection:
                for candidate, sources in admitted:
                    assert candidate.coordinate is not None
                    canonical = self._hash("|".join((
                        candidate.kind,
                        candidate.title.strip().lower(),
                        f"{candidate.coordinate.latitude:.4f}",
                        f"{candidate.coordinate.longitude:.4f}",
                    )))
                    await connection.execute(place_sql, {
                        "id": canonical,
                        "canonical_key": canonical,
                        "kind": candidate.kind,
                        "name": candidate.title,
                        "summary": candidate.summary,
                        "valid_until": freshness_until(job.region.mission_type, candidate.ends_at),
                        "latitude": candidate.coordinate.latitude,
                        "longitude": candidate.coordinate.longitude,
                        "starts_at": candidate.starts_at,
                        "ends_at": candidate.ends_at,
                    })
                    for source in sources:
                        source_id = self._hash(str(source.url))
                        await connection.execute(source_sql, {
                            "id": source_id,
                            "source_id": source.source_id,
                            "source_version": source.source_version,
                            "url": str(source.url),
                            "title": source.title,
                            "snippet": source.snippet,
                            "publisher": source.publisher,
                            "published_at": source.published_at,
                        })
                        await connection.execute(evidence_sql, {
                            "id": self._hash(f"{canonical}|{source_id}"),
                            "place_id": canonical,
                            "source_document_id": source_id,
                            "provider": source.publisher,
                            "title": source.title,
                            "url": str(source.url),
                            "license": source.license,
                            "source_version": source.source_version,
                            "published_at": source.published_at,
                        })
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error
        return len(admitted)

    @staticmethod
    def _hash(value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()
