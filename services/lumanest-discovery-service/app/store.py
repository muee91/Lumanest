from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone

from redis.asyncio import Redis
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from .models import DiscoveryItem, DiscoveryRequest, DiscoveryResponse


CACHE_SECONDS = 600
PENDING_SECONDS = 1800
REFRESH_STREAM = "discovery:refresh:stream"
REFRESH_GROUP = "discovery-workers"


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
    def fingerprint(request: DiscoveryRequest) -> str:
        # Round to about 110 m: sufficient for a regional cache and avoids using a raw
        # coordinate as a Redis key or task payload.
        payload = {
            "latitude": round(request.coordinate.latitude, 3),
            "longitude": round(request.coordinate.longitude, 3),
            "locale": request.locale.lower(),
            "focus": request.focus,
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
                CACHE_SECONDS,
                response.model_dump_json(by_alias=True),
            )
        except Exception:
            return

    async def refresh_state(self, fingerprint: str) -> str | None:
        if self.redis is None:
            return None
        try:
            return await self.redis.get(f"discovery:refresh:{fingerprint}")
        except Exception:
            return None

    async def schedule_refresh(self, fingerprint: str) -> bool:
        """Deduplicate a source refresh request without retaining a coordinate."""
        if self.redis is None:
            return False
        key = f"discovery:refresh:{fingerprint}"
        try:
            if not await self.redis.set(key, "pending", ex=PENDING_SECONDS, nx=True):
                return False
            await self.redis.xadd(REFRESH_STREAM, {"fingerprint": fingerprint}, maxlen=10_000, approximate=True)
            return True
        except Exception:
            return False

    async def candidates(self, request: DiscoveryRequest) -> list[DiscoveryItem]:
        if self.engine is None:
            raise RuntimeError("storage_not_configured")
        kind_filter = {
            "photography": ("candidate_viewpoint",),
            "water": ("attraction",),
            "humanity": ("event",),
        }[request.focus]
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
                   evidence.retrieved_at
            FROM discovery.places AS places
            JOIN LATERAL (
                SELECT provider, title, source_url, retrieved_at
                FROM discovery.evidence
                WHERE place_id = places.id
                  AND review_status = 'approved'
                  AND title IS NOT NULL
                  AND title <> ''
                ORDER BY retrieved_at DESC
                LIMIT 4
            ) AS evidence ON TRUE
            WHERE places.published = TRUE
              AND places.kind = ANY(CAST(:kinds AS text[]))
              AND (places.valid_until IS NULL OR places.valid_until > NOW())
              AND ST_DWithin(
                    places.geometry::geography,
                    ST_SetSRID(ST_Point(:longitude, :latitude), 4326)::geography,
                    20000
              )
            ORDER BY distance_meters ASC, places.updated_at DESC
            LIMIT 80
        """)
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(
                    query,
                    {
                        "latitude": request.coordinate.latitude,
                        "longitude": request.coordinate.longitude,
                        "kinds": list(kind_filter),
                    },
                )).mappings().all()
        except SQLAlchemyError as error:
            raise RuntimeError("storage_unavailable") from error

        grouped: dict[str, dict] = {}
        for row in rows:
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

        refresh_state = await self.refresh_state(fingerprint)
        now = datetime.now(timezone.utc)
        if refresh_state == "pending":
            return DiscoveryResponse(
                status="pending",
                generatedAt=now,
                expiresAt=None,
                retryAfterSeconds=30,
                items=[],
            ), 202

        items = await self.candidates(request)
        response = DiscoveryResponse(
            status="ready" if items else "refreshing",
            generatedAt=now,
            expiresAt=now + timedelta(seconds=CACHE_SECONDS) if items else None,
            retryAfterSeconds=None if items else 30,
            items=items,
        )
        if items:
            await self.cache(fingerprint, response)
        if not items:
            await self.schedule_refresh(fingerprint)
        return response, 200
