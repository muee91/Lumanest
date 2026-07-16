from __future__ import annotations

import asyncio
import os

from redis.asyncio import Redis
from redis.exceptions import ResponseError

from .store import REFRESH_GROUP, REFRESH_STREAM


HEARTBEAT_KEY = "discovery:worker:heartbeat"


async def run() -> None:
    redis_url = os.getenv("REDIS_URL")
    if not redis_url:
        raise RuntimeError("REDIS_URL is required")
    client = Redis.from_url(redis_url, decode_responses=True)
    try:
        try:
            await client.xgroup_create(REFRESH_STREAM, REFRESH_GROUP, id="0", mkstream=True)
        except ResponseError as error:
            if "BUSYGROUP" not in str(error):
                raise
        while True:
            await client.set(HEARTBEAT_KEY, "ok", ex=20)
            batches = await client.xreadgroup(
                REFRESH_GROUP,
                "discovery-worker-1",
                {REFRESH_STREAM: ">"},
                count=1,
                block=5000,
            )
            if not batches:
                continue
            _, entries = batches[0]
            entry_id, values = entries[0]
            fingerprint = values.get("fingerprint")
            if not fingerprint:
                await client.xack(REFRESH_STREAM, REFRESH_GROUP, entry_id)
                continue
            # Discovery ingestion is deliberately not coupled to this core. This
            # transition gives future approved providers one idempotent hand-off
            # point without recording coordinates or initiating a crawl here.
            await client.set(f"discovery:refresh:{fingerprint}", "attempted", ex=21_600)
            await client.xack(REFRESH_STREAM, REFRESH_GROUP, entry_id)
    finally:
        await client.aclose()


if __name__ == "__main__":
    asyncio.run(run())
