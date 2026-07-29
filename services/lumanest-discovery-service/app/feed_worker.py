from __future__ import annotations

import asyncio
import hashlib
import math
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from urllib.parse import urljoin, urlsplit

import httpx
from redis.asyncio import Redis

from .crawl.selectors import select_evidence
from .crawl.url_guard import UrlPolicy, UrlRejected, guard_url
from .feed import (
    FEED_STATUS_HASH,
    FeedFetchState,
    FeedRegistry,
    FeedSourceDefinition,
    MAX_FEED_BYTES,
    parse_feed_document,
    parse_static_document,
)
from .models import BrokerSearchResult, ExtractedCandidate
from .store import DiscoveryStore, RefreshJob, RegionReference
from .worker import BrokerClient, BrokerFailure, is_admissible


FEED_HEARTBEAT_KEY = "discovery:feed-worker:heartbeat"
POLL_SECONDS = 30
MAX_REDIRECTS = 2
MAX_FAILURE_BACKOFF_SECONDS = 6 * 60 * 60


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _region_reference(source: FeedSourceDefinition, mission_type: str) -> RegionReference:
    latitude_cell = math.floor(source.region.latitude / 0.05)
    longitude_cell = math.floor(source.region.longitude / 0.05)
    return RegionReference(
        region_id=f"g{latitude_cell}:{longitude_cell}",
        latitude=round((latitude_cell + 0.5) * 0.05, 3),
        longitude=round((longitude_cell + 0.5) * 0.05, 3),
        locale=source.locale,
        mission_type=mission_type,
        focus=source.title,
        radius_meters=source.region.radius_meters,
    )


def _refresh_job(
    source: FeedSourceDefinition,
    mission_type: str,
    content_hash: str,
) -> RefreshJob:
    region = _region_reference(source, mission_type)
    fingerprint = hashlib.sha256(
        f"feed|{source.id}|{mission_type}|{content_hash}".encode("utf-8")
    ).hexdigest()
    dedupe_key = hashlib.sha256(
        f"feed|{source.id}|{mission_type}".encode("utf-8")
    ).hexdigest()
    return RefreshJob(
        fingerprint=fingerprint,
        region=region,
        expires_at=int(time.time()) + max(source.refresh_interval_seconds, 1800),
        attempt=0,
        activation_type="admin_backfill",
        dedupe_key=dedupe_key,
    )


def _host(value: str) -> str:
    return (urlsplit(value).hostname or "").casefold().rstrip(".")


async def _get_bounded(
    client: httpx.AsyncClient,
    source: FeedSourceDefinition,
    state: FeedFetchState,
    *,
    resolve_dns: bool = True,
) -> tuple[int, bytes | None, str | None, str | None]:
    initial = str(source.feed_url)
    domain = _host(initial)
    if not domain:
        raise ValueError("feed_host_missing")
    policy = UrlPolicy(domain=domain)
    current = guard_url(initial, policy, resolve_dns=resolve_dns)
    headers = {
        "Accept": "application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9, text/html;q=0.8",
        "User-Agent": "LumaNest-FeedEvidence/1.0",
    }
    if state.etag:
        headers["If-None-Match"] = state.etag
    if state.last_modified:
        headers["If-Modified-Since"] = state.last_modified

    for redirect_count in range(MAX_REDIRECTS + 1):
        response = await client.get(current, headers=headers, follow_redirects=False)
        if response.status_code in {301, 302, 303, 307, 308}:
            if redirect_count >= MAX_REDIRECTS:
                raise ValueError("feed_redirect_limit")
            location = response.headers.get("location")
            if not location:
                raise ValueError("feed_redirect_invalid")
            current = guard_url(
                urljoin(current, location),
                policy,
                resolve_dns=resolve_dns,
            )
            continue
        if response.status_code == 304:
            return 304, None, response.headers.get("etag") or state.etag, (
                response.headers.get("last-modified") or state.last_modified
            )
        if response.status_code != 200:
            raise ValueError(f"feed_http_{response.status_code}")
        content_length = response.headers.get("content-length")
        if content_length and content_length.isdigit() and int(content_length) > MAX_FEED_BYTES:
            raise ValueError("feed_size_invalid")
        payload = response.content
        if not payload or len(payload) > MAX_FEED_BYTES:
            raise ValueError("feed_size_invalid")
        return (
            200,
            payload,
            response.headers.get("etag"),
            response.headers.get("last-modified"),
        )
    raise ValueError("feed_redirect_limit")


async def fetch_feed(
    source: FeedSourceDefinition,
    state: FeedFetchState,
    *,
    client: httpx.AsyncClient | None = None,
    resolve_dns: bool = True,
) -> tuple[list[BrokerSearchResult] | None, str | None, str | None, str | None]:
    owns_client = client is None
    if client is None:
        client = httpx.AsyncClient(
            timeout=httpx.Timeout(15.0),
            trust_env=True,
        )
    try:
        status, payload, etag, last_modified = await _get_bounded(
            client,
            source,
            state,
            resolve_dns=resolve_dns,
        )
        if status == 304 or payload is None:
            return None, state.content_hash, etag, last_modified
        content_hash = hashlib.sha256(payload).hexdigest()
        if content_hash == state.content_hash:
            return None, content_hash, etag, last_modified
        evidence = (
            parse_static_document(payload, source)
            if source.content_kind == "document"
            else parse_feed_document(payload, source)
        )
        return evidence, content_hash, etag, last_modified
    finally:
        if owns_client:
            await client.aclose()


async def _extract_and_persist(
    store: DiscoveryStore,
    broker: BrokerClient,
    source: FeedSourceDefinition,
    evidence: list[BrokerSearchResult],
    content_hash: str,
) -> None:
    for mission_type in source.mission_types:
        job = _refresh_job(source, mission_type, content_hash)
        selected = select_evidence(
            evidence,
            mission_type=mission_type,
            focus=source.title,
            maximum=8,
            max_per_domain=8,
            source_tiers={source.source_id: source.quality_tier},
        )
        if not selected:
            continue
        extracted, insights = await broker.extract_with_insights(job, selected)
        evidence_pool = list(selected)
        resolved_candidates: list[ExtractedCandidate] = []
        for candidate in extracted:
            if candidate.coordinate is not None:
                resolved_candidates.append(candidate)
                continue
            resolved = await broker.resolve_place(job, candidate)
            if resolved is None:
                continue
            resolved_candidate, coordinate_evidence = resolved
            resolved_candidate = resolved_candidate.model_copy(
                update={
                    "source_indexes": [
                        *resolved_candidate.source_indexes[:3],
                        len(evidence_pool),
                    ]
                }
            )
            evidence_pool.append(coordinate_evidence)
            resolved_candidates.append(resolved_candidate)

        admitted = [
            (candidate, linked)
            for candidate in resolved_candidates
            if (linked := is_admissible(candidate, evidence_pool, job))
        ]
        if insights:
            await store.persist_region_insights(job, insights, evidence_pool)
        await store.persist_candidates(job, admitted)


def _next_success(source: FeedSourceDefinition, now: datetime) -> datetime:
    return now + timedelta(seconds=source.refresh_interval_seconds)


def _next_failure(
    source: FeedSourceDefinition,
    state: FeedFetchState,
    now: datetime,
) -> datetime:
    failures = min(state.failure_count + 1, 8)
    delay = min(
        source.refresh_interval_seconds * (2 ** min(failures - 1, 5)),
        MAX_FAILURE_BACKOFF_SECONDS,
    )
    return now + timedelta(seconds=max(delay, 900))


def _failure_text(error: Exception) -> str:
    return f"{type(error).__name__}:{str(error)[:120]}"


async def process_source(
    registry: FeedRegistry,
    store: DiscoveryStore,
    broker: BrokerClient,
    source: FeedSourceDefinition,
    *,
    client: httpx.AsyncClient | None = None,
    resolve_dns: bool = True,
) -> None:
    current_state = await registry.get(source.id)
    state = FeedFetchState(
        last_success_at=current_state.last_success_at if current_state else None,
        next_refresh_at=current_state.next_refresh_at if current_state else None,
        last_error=current_state.last_error if current_state else None,
        item_count=current_state.item_count if current_state else 0,
        failure_count=0,
    )
    if registry.redis is not None:
        state = FeedFetchState.from_json(
            await registry.redis.hget(FEED_STATUS_HASH, source.id)
        )

    now = _now()
    try:
        evidence, content_hash, etag, last_modified = await fetch_feed(
            source,
            state,
            client=client,
            resolve_dns=resolve_dns,
        )
        if evidence is not None and content_hash is not None:
            await _extract_and_persist(store, broker, source, evidence, content_hash)
            item_count = len(evidence)
        else:
            item_count = state.item_count
        await registry.set_status(
            source.id,
            FeedFetchState(
                etag=etag or state.etag,
                last_modified=last_modified or state.last_modified,
                content_hash=content_hash or state.content_hash,
                last_success_at=now,
                next_refresh_at=_next_success(source, now),
                last_error=None,
                item_count=item_count,
                failure_count=0,
            ),
        )
    except (BrokerFailure, RuntimeError, ValueError, httpx.HTTPError, UrlRejected) as error:
        await registry.set_status(
            source.id,
            FeedFetchState(
                etag=state.etag,
                last_modified=state.last_modified,
                content_hash=state.content_hash,
                last_success_at=state.last_success_at,
                next_refresh_at=_next_failure(source, state, now),
                last_error=_failure_text(error),
                item_count=state.item_count,
                failure_count=min(state.failure_count + 1, 8),
            ),
        )
        print(
            f"feed refresh failed source={source.id} code={str(error)[:120]}",
            flush=True,
        )


async def run_once(
    registry: FeedRegistry,
    store: DiscoveryStore,
    broker: BrokerClient,
    *,
    client: httpx.AsyncClient | None = None,
) -> int:
    listing = await registry.list()
    now = _now()
    due = [
        state.source
        for state in listing.sources
        if state.source.enabled
        and (state.next_refresh_at is None or state.next_refresh_at <= now)
    ]
    if not due:
        return 0
    semaphore = asyncio.Semaphore(
        max(1, min(int(os.getenv("DISCOVERY_FEED_CONCURRENCY", "3")), 8))
    )

    async def guarded(source: FeedSourceDefinition) -> None:
        async with semaphore:
            redis = registry.redis
            if redis is None:
                raise RuntimeError("feed_registry_not_configured")
            lock_key = f"discovery:feed:lock:{source.id}"
            lock_token = uuid.uuid4().hex
            locked = await redis.set(lock_key, lock_token, nx=True, ex=600)
            if not locked:
                return
            try:
                await process_source(
                    registry,
                    store,
                    broker,
                    source,
                    client=client,
                )
            finally:
                await redis.eval(
                    "if redis.call('get', KEYS[1]) == ARGV[1] then "
                    "return redis.call('del', KEYS[1]) else return 0 end",
                    1,
                    lock_key,
                    lock_token,
                )

    await asyncio.gather(*(guarded(source) for source in due))
    return len(due)


async def run() -> None:
    redis_url = os.getenv("REDIS_URL")
    database_url = os.getenv("DATABASE_URL")
    if not redis_url or not database_url:
        raise RuntimeError("DATABASE_URL and REDIS_URL are required")
    redis = Redis.from_url(redis_url, decode_responses=True)
    registry = FeedRegistry(redis)
    store = DiscoveryStore(database_url, None)
    broker = BrokerClient(
        os.getenv("DISCOVERY_BROKER_URL", "").rstrip("/"),
        os.getenv("DISCOVERY_WORKER_TOKEN", ""),
    )
    if not broker.configured:
        raise RuntimeError("feed broker is not configured")
    await registry.bootstrap(os.getenv("DISCOVERY_FEED_SOURCES_JSON"))
    try:
        while True:
            await redis.set(FEED_HEARTBEAT_KEY, "ok", ex=90)
            await run_once(registry, store, broker)
            await asyncio.sleep(
                max(
                    10,
                    min(
                        int(os.getenv("DISCOVERY_FEED_POLL_SECONDS", str(POLL_SECONDS))),
                        300,
                    ),
                )
            )
    finally:
        await store.close()
        await redis.aclose()


if __name__ == "__main__":
    asyncio.run(run())
