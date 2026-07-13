from __future__ import annotations

import json

from redis.asyncio import Redis
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from .models import SceneEvidence, SourceStatus


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
            SELECT kind
            FROM spatial_features
            WHERE enabled = TRUE
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
        kinds = set(rows)
        return SceneEvidence(
            urban="urban" in kinds,
            waterBody="water" in kinds,
            mountainous="mountain" in kinds,
            aridLand="arid" in kinds,
            settlement="settlement" in kinds,
        )

    async def cached_snapshot(self, fingerprint: str) -> dict | None:
        if self.redis is None:
            return None
        try:
            raw = await self.redis.get(f"context:v2:{fingerprint}")
            return json.loads(raw) if raw else None
        except Exception:
            return None

    async def cache_snapshot(self, fingerprint: str, body: dict) -> None:
        if self.redis is None:
            return
        try:
            await self.redis.setex(f"context:v2:{fingerprint}", 900, json.dumps(body, separators=(",", ":")))
        except Exception:
            return

    async def source_statuses(self) -> list[SourceStatus]:
        if self.engine is None:
            return []
        try:
            async with self.engine.connect() as connection:
                rows = (await connection.execute(text("""
                    SELECT id, enabled, license_status, attribution, updated_at
                    FROM source_registry ORDER BY id
                """))).mappings().all()
            return [SourceStatus.model_validate(dict(row)) for row in rows]
        except Exception:
            return []
