from __future__ import annotations

import asyncio
import hashlib
import json
import os
import time
from dataclasses import dataclass
from typing import Any

import httpx
from redis.asyncio import Redis
from redis.exceptions import ResponseError

from .models import (
    BrokerDeterministicResponse,
    BrokerExtractionResponse,
    BrokerSearchResponse,
    BrokerSearchResult,
    ExtractionCoordinate,
    ExtractedCandidate,
    ExtractedRegionInsight,
    PlaceResolutionRequest,
    PlaceResolutionResponse,
)
from .crawl.selectors import select_evidence
from .crawl.client import Crawl4AIPageCrawler, PageCrawler
from .crawl.url_guard import UrlPolicy, UrlRejected
from .store import (
    PENDING_SECONDS,
    REFRESH_GROUP,
    REFRESH_STREAM,
    DiscoveryStore,
    RefreshJob,
    RegionReference,
)


HEARTBEAT_KEY = "discovery:worker:heartbeat"
MAX_RETRIES = 2
FAILED_COOLDOWN_SECONDS = 5 * 60
CRAWL_CACHE_SECONDS = 6 * 60 * 60
CRAWL_FAILURE_CACHE_SECONDS = 15 * 60
CRAWL_MIN_SNIPPET_CHARS = 260
MAX_CRAWLS_PER_JOB = 3
FORBIDDEN_CONTENT = (
    "wildlife", "animal", "bear", "tiger", "snake", "risk", "danger", "hazard", "warning",
    "emergency", "safety", "popular", "trending", "top", "热度", "热门", "人气",
    "野生动物", "动物", "熊", "老虎", "蛇", "风险", "危险", "预警", "安全",
)


class BrokerFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class BrokerClient:
    base_url: str
    token: str

    @property
    def configured(self) -> bool:
        return bool(self.base_url and self.token)

    async def search(self, job: RefreshJob) -> list[BrokerSearchResult]:
        results: list[BrokerSearchResult] = []
        seen: set[str] = set()
        for query in self._queries(job):
            payload = {
                "query": query,
                "locale": job.region.locale,
                "freshnessDays": self._freshness_days(job.region.mission_type),
                "domains": [],
            }
            raw = await self._post("/internal/v1/discovery/search", payload)
            try:
                response = BrokerSearchResponse.model_validate(raw)
            except Exception as error:
                raise BrokerFailure("invalid_search_response") from error
            for item in response.results:
                url = str(item.url)
                if item.url.scheme == "https" and url not in seen:
                    seen.add(url)
                    results.append(item)
                if len(results) == 24:
                    return results
        return results

    async def extract(
        self,
        job: RefreshJob,
        evidence: list[BrokerSearchResult],
    ) -> list[ExtractedCandidate]:
        candidates, _ = await self.extract_with_insights(job, evidence)
        return candidates

    async def extract_with_insights(
        self,
        job: RefreshJob,
        evidence: list[BrokerSearchResult],
    ) -> tuple[list[ExtractedCandidate], list[ExtractedRegionInsight]]:
        payload = {
            "missionType": job.region.mission_type,
            "focus": job.region.focus,
            "locale": job.region.locale,
            "region": {"latitude": job.region.latitude, "longitude": job.region.longitude},
            "evidence": [{
                "title": item.title,
                "snippet": item.snippet,
                "url": str(item.url),
                **({"publishedAt": item.published_at.isoformat()} if item.published_at else {}),
                "sourceId": item.source_id,
                "publisher": item.publisher,
                "license": item.license,
                "version": item.source_version,
                "qualityTier": item.quality_tier,
            } for item in evidence],
        }
        raw = await self._post("/internal/v1/discovery/extract", payload)
        try:
            response = BrokerExtractionResponse.model_validate(raw)
            return response.candidates, response.insights
        except Exception as error:
            raise BrokerFailure("invalid_extraction_response") from error

    async def deterministic(
        self,
        job: RefreshJob,
        evidence: list[BrokerSearchResult],
    ) -> tuple[list[ExtractedCandidate], list[BrokerSearchResult]]:
        payload = {
            "missionType": job.region.mission_type,
            "focus": job.region.focus,
            "locale": job.region.locale,
            "region": {
                "latitude": job.region.latitude,
                "longitude": job.region.longitude,
                "radiusMeters": job.region.radius_meters,
            },
            "evidence": [item.model_dump(by_alias=True, mode="json") for item in evidence],
        }
        raw = await self._post("/internal/v1/discovery/deterministic", payload)
        try:
            response = BrokerDeterministicResponse.model_validate(raw)
            return response.candidates, response.evidence
        except Exception as error:
            raise BrokerFailure("invalid_deterministic_response") from error

    async def resolve_place(self, job: RefreshJob, candidate: ExtractedCandidate) -> tuple[ExtractedCandidate, BrokerSearchResult] | None:
        payload = PlaceResolutionRequest(
            query=candidate.title,
            addressHint=candidate.address_hint,
            region={
                "latitude": job.region.latitude,
                "longitude": job.region.longitude,
                "radiusMeters": job.region.radius_meters,
            },
            locale=job.region.locale,
        ).model_dump(by_alias=True, mode="json")
        raw = await self._post("/internal/v1/discovery/resolve-place", payload)
        try:
            response = PlaceResolutionResponse.model_validate(raw)
        except Exception as error:
            raise BrokerFailure("invalid_place_resolution_response") from error
        if response.status != "resolved" or response.place is None or response.evidence is None:
            return None
        coordinate = response.place.get("coordinate")
        if not isinstance(coordinate, dict):
            return None
        resolved = candidate.model_copy(update={
            "coordinate": ExtractionCoordinate.model_validate(coordinate),
            "coordinate_evidence": response.evidence.snippet.split("坐标：")[-1][:120],
        })
        return resolved, response.evidence

    async def _post(self, path: str, payload: dict[str, Any]) -> Any:
        if not self.configured:
            raise BrokerFailure("broker_not_configured")
        try:
            async with httpx.AsyncClient(base_url=self.base_url, timeout=httpx.Timeout(12.0)) as client:
                response = await client.post(
                    path,
                    json=payload,
                    headers={"X-Discovery-Worker-Token": self.token},
                )
                if response.status_code != 200:
                    raise BrokerFailure("broker_unavailable")
                return response.json()
        except (httpx.HTTPError, ValueError) as error:
            raise BrokerFailure("broker_unavailable") from error

    @staticmethod
    def _queries(job: RefreshJob) -> tuple[str, str, str]:
        # Coordinates are the coarse grid centre, never the app's raw point.
        area = job.region.focus.strip() or f"{job.region.latitude:.3f},{job.region.longitude:.3f}"
        if not job.region.locale.startswith("zh"):
            return (
                f"{area} {job.region.mission_type} recent",
                f"{area} {job.region.mission_type} official",
                f"{area} {job.region.mission_type} local",
            )
        templates = {
            "popularPlaces": ("最近热门 地点", "摄影机位", "本月 热门旅行地点"),
            "hiddenPlaces": ("小众地点", "本地人常去", "非热门摄影地点"),
            "humanityEvents": ("今日 市集 活动", "本周 民俗 节庆", "早市 夜市 展览"),
            "localStories": ("历史", "当地文化", "传统手艺"),
            "routeConditions": ("当前路况", "临时封闭", "施工 管制"),
            "openingAndClosure": ("今日开放", "临时关闭", "营业时间"),
            "seasonalSignals": ("本月 花期", "候鸟", "季节景观"),
            "localFoodAndSpecialties": ("本地特色 食物", "传统小吃", "地方特产"),
            "culturalEtiquette": ("参观礼仪", "当地习俗", "拍摄礼仪"),
        }[job.region.mission_type]
        return tuple(f"{area} {suffix}" for suffix in templates)

    @staticmethod
    def _freshness_days(mission_type: str) -> int:
        return {
            "routeConditions": 1,
            "humanityEvents": 1,
            "openingAndClosure": 1,
            "popularPlaces": 1,
            "hiddenPlaces": 3,
            "seasonalSignals": 1,
            "localStories": 30,
            "localFoodAndSpecialties": 14,
            "culturalEtiquette": 30,
        }[mission_type]


def parse_job(values: dict[str, str]) -> RefreshJob | None:
    """Validate a queue record and reject any non-coarse/expired work item."""
    try:
        fingerprint = values["fingerprint"]
        region_id = values["regionId"]
        latitude = float(values["latitude"])
        longitude = float(values["longitude"])
        locale = values["locale"]
        focus = values["focus"]
        mission_type = values["missionType"]
        radius_meters = int(values["radiusMeters"])
        expires_at = int(values["expiresAt"])
        attempt = int(values.get("attempt", "0"))
        activation_type = values["activationType"]
        dedupe_key = values["dedupeKey"]
    except (KeyError, TypeError, ValueError):
        return None
    if (
        len(fingerprint) != 64 or len(region_id) > 80 or not -90 <= latitude <= 90
        or not -180 <= longitude <= 180 or mission_type not in {
            "popularPlaces", "hiddenPlaces", "humanityEvents", "localStories",
            "routeConditions", "openingAndClosure", "seasonalSignals",
            "localFoodAndSpecialties", "culturalEtiquette",
        } or not 100 <= radius_meters <= 50_000
        or not 0 <= attempt <= MAX_RETRIES or expires_at <= int(time.time())
        or activation_type not in {"user_manual", "foreground_opportunistic", "ai_verification", "admin_backfill"}
        or len(dedupe_key) != 64
    ):
        return None
    # Stream values must itself be a grid-centre, not a conveniently rounded raw point.
    if abs((latitude / 0.05 - 0.5) - round(latitude / 0.05 - 0.5)) > 0.0001:
        return None
    if abs((longitude / 0.05 - 0.5) - round(longitude / 0.05 - 0.5)) > 0.0001:
        return None
    return RefreshJob(
        fingerprint=fingerprint,
        region=RegionReference(
            region_id, latitude, longitude, locale, mission_type, focus, radius_meters
        ),
        expires_at=expires_at,
        attempt=attempt,
        activation_type=activation_type,
        dedupe_key=dedupe_key,
    )


def is_admissible(candidate: ExtractedCandidate, evidence: list[BrokerSearchResult], job: RefreshJob) -> list[BrokerSearchResult] | None:
    """Admission gate: source-linked, nearby, creative discovery only."""
    if candidate.coordinate is None:
        return None
    if not coordinate_evidence_supports(candidate, evidence):
        return None
    if not has_normal_coordinate_precision(candidate.coordinate.latitude) or not has_normal_coordinate_precision(candidate.coordinate.longitude):
        return None
    content = " ".join(filter(None, (candidate.title, candidate.summary))).lower()
    if any(term in content for term in FORBIDDEN_CONTENT):
        return None
    if candidate.ends_at and candidate.starts_at and candidate.ends_at < candidate.starts_at:
        return None
    if any(index < 0 or index >= len(evidence) for index in candidate.source_indexes):
        return None
    linked = [evidence[index] for index in dict.fromkeys(candidate.source_indexes)]
    if not linked or any(item.url.scheme != "https" for item in linked):
        return None
    if distance_km(
        job.region.latitude,
        job.region.longitude,
        candidate.coordinate.latitude,
        candidate.coordinate.longitude,
    ) > 50:
        return None
    return linked


def is_deterministic_admissible(
    candidate: ExtractedCandidate,
    evidence: list[BrokerSearchResult],
    job: RefreshJob,
) -> list[BrokerSearchResult] | None:
    """Accept only the dedicated AMap products for their matching mission."""
    expected = {
        "routeConditions": ("amap-traffic", "candidate_viewpoint"),
        "openingAndClosure": ("amap-poi", "attraction"),
    }.get(job.region.mission_type)
    if expected is None or candidate.kind != expected[1]:
        return None
    if candidate.coordinate is None or not coordinate_evidence_supports(candidate, evidence):
        return None
    if not has_normal_coordinate_precision(candidate.coordinate.latitude) or not has_normal_coordinate_precision(candidate.coordinate.longitude):
        return None
    if any(index < 0 or index >= len(evidence) for index in candidate.source_indexes):
        return None
    linked = [evidence[index] for index in dict.fromkeys(candidate.source_indexes)]
    if not linked or any(
        item.source_id != expected[0]
        or item.publisher != "高德地图"
        or item.url.host != "ditu.amap.com"
        or item.url.scheme != "https"
        for item in linked
    ):
        return None
    if distance_km(
        job.region.latitude,
        job.region.longitude,
        candidate.coordinate.latitude,
        candidate.coordinate.longitude,
    ) > 50:
        return None
    return linked


def coordinate_evidence_supports(candidate: ExtractedCandidate, evidence: list[BrokerSearchResult]) -> bool:
    """Do not publish a model coordinate unless source text contains the exact pair."""
    import re

    raw = candidate.coordinate_evidence
    if raw is None or candidate.coordinate is None or len(raw) > 120:
        return False
    match = re.fullmatch(r"\s*(-?\d{1,2}(?:\.\d{1,6})?)\s*,\s*(-?\d{1,3}(?:\.\d{1,6})?)\s*", raw)
    if match is None:
        return False
    linked = [evidence[index] for index in dict.fromkeys(candidate.source_indexes)
              if 0 <= index < len(evidence)]
    if not any(raw in f"{source.title}\n{source.snippet}" for source in linked):
        return False
    first, second = map(float, match.groups())
    latitude, longitude = candidate.coordinate.latitude, candidate.coordinate.longitude
    tolerance = 0.00001
    return ((abs(first - latitude) <= tolerance and abs(second - longitude) <= tolerance) or
            (abs(second - latitude) <= tolerance and abs(first - longitude) <= tolerance))


def has_normal_coordinate_precision(value: float) -> bool:
    """Reject unusually precise model coordinates; this feature is not tracking."""
    rendered = f"{value:.8f}".rstrip("0").rstrip(".")
    fractional = rendered.partition(".")[2]
    return len(fractional) <= 5


def distance_km(latitude_a: float, longitude_a: float, latitude_b: float, longitude_b: float) -> float:
    """Haversine distance, sufficient for an admission boundary rather than navigation."""
    from math import asin, cos, radians, sin, sqrt

    latitude_delta = radians(latitude_b - latitude_a)
    longitude_delta = radians(longitude_b - longitude_a)
    value = sin(latitude_delta / 2) ** 2 + cos(radians(latitude_a)) * cos(radians(latitude_b)) * sin(longitude_delta / 2) ** 2
    return 6371.0 * 2 * asin(sqrt(value))


async def retry_or_fail(redis: Redis, store: DiscoveryStore, job: RefreshJob) -> None:
    next_attempt = job.attempt + 1
    key = f"discovery:refresh:{job.dedupe_key}"
    if next_attempt > MAX_RETRIES:
        await redis.set(key, "failed", ex=PENDING_SECONDS)
        await redis.set(
            f"discovery:cooldown:{job.dedupe_key}",
            "failed",
            ex=FAILED_COOLDOWN_SECONDS,
        )
        await store.record_refresh(job, "failed")
        return
    retry = RefreshJob(
        job.fingerprint,
        job.region,
        job.expires_at,
        next_attempt,
        job.activation_type,
        job.dedupe_key,
    )
    await redis.set(key, f"retry:{next_attempt}", ex=PENDING_SECONDS)
    await redis.xadd(REFRESH_STREAM, retry.stream_values(), maxlen=10_000, approximate=True)
    await store.record_refresh(retry, "attempted")


def _crawler_enabled() -> bool:
    return os.getenv("DISCOVERY_CRAWLER_ENABLED", "true").strip().lower() in {"1", "true", "yes", "on"}


def _crawl_cache_key(item: BrokerSearchResult) -> str:
    return f"discovery:crawl:{hashlib.sha256(str(item.url).encode('utf-8')).hexdigest()}"


def _cleaned_window(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = " ".join(value.split()).strip()
    return normalized[:1_200] if len(normalized) >= 80 else None


async def enrich_evidence_with_crawl(
    redis: Redis,
    evidence: list[BrokerSearchResult],
    crawler: PageCrawler | None,
) -> list[BrokerSearchResult]:
    """Use Crawl4AI only when search snippets are too thin for extraction.

    Every page URL first passed Broker source-policy validation. The crawler
    pins the request and any redirect to that exact host, caches only a bounded
    cleaned text window, and never creates a candidate by itself.
    """
    if crawler is None or not evidence:
        return evidence
    needs_more_context = len(evidence) < 3 or any(len(item.snippet.strip()) < CRAWL_MIN_SNIPPET_CHARS for item in evidence)
    if not needs_more_context:
        return evidence
    replacements: dict[str, BrokerSearchResult] = {}
    for item in evidence[:MAX_CRAWLS_PER_JOB]:
        key = _crawl_cache_key(item)
        cached = None
        try:
            cached = await redis.get(key)
        except Exception:
            cached = None
        if cached:
            try:
                window = _cleaned_window(json.loads(cached).get("window"))
            except (TypeError, ValueError, json.JSONDecodeError):
                window = None
            if window is not None:
                replacements[str(item.url)] = item.model_copy(update={"snippet": window})
                continue
        try:
            hostname = item.url.host
            if not hostname:
                continue
            result = await crawler.crawl(str(item.url), UrlPolicy(domain=hostname))
            window = _cleaned_window(result.get("cleanedMarkdown")) if result.get("status") == "success" else None
        except (UrlRejected, ValueError, OSError):
            window = None
        except Exception:
            window = None
        try:
            if window is None:
                await redis.setex(key, CRAWL_FAILURE_CACHE_SECONDS, json.dumps({"window": None}))
            else:
                await redis.setex(key, CRAWL_CACHE_SECONDS, json.dumps({"window": window}))
        except Exception:
            pass
        if window is not None:
            replacements[str(item.url)] = item.model_copy(update={"snippet": window})
    return [replacements.get(str(item.url), item) for item in evidence]


async def process_job(
    redis: Redis,
    store: DiscoveryStore,
    broker: BrokerClient,
    job: RefreshJob,
    crawler: PageCrawler | None = None,
) -> None:
    try:
        await store.record_refresh(job, "attempted")
        if job.region.mission_type in {"routeConditions", "openingAndClosure"}:
            extracted, deterministic_evidence = await broker.deterministic(job, [])
            admitted = [
                (candidate, linked)
                for candidate in extracted
                if (linked := is_deterministic_admissible(
                    candidate, deterministic_evidence, job
                ))
            ]
        else:
            evidence = await broker.search(job)
            if not evidence:
                await redis.set(f"discovery:refresh:{job.dedupe_key}", "completed", ex=CACHE_TTL)
                await store.record_refresh(job, "completed")
                return
            selected = select_evidence(
                evidence,
                mission_type=job.region.mission_type,
                focus=job.region.focus,
                maximum=8,
                max_per_domain=2,
            )
            if not selected:
                await redis.set(f"discovery:refresh:{job.dedupe_key}", "completed", ex=CACHE_TTL)
                await store.record_refresh(job, "completed")
                return
            selected = await enrich_evidence_with_crawl(redis, selected, crawler)
            if isinstance(broker, BrokerClient):
                extracted, extracted_insights = await broker.extract_with_insights(
                    job,
                    selected,
                )
            else:
                # Existing worker fakes and alternate implementations expose
                # the original candidate-only method. They remain valid and
                # simply have no regional facts to persist.
                extracted = await broker.extract(job, selected)
                extracted_insights = []
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
                resolved_candidate = resolved_candidate.model_copy(update={
                    "source_indexes": [*resolved_candidate.source_indexes[:3], len(evidence_pool)],
                })
                evidence_pool.append(coordinate_evidence)
                resolved_candidates.append(resolved_candidate)
            admitted = [(candidate, linked) for candidate in resolved_candidates if (linked := is_admissible(candidate, evidence_pool, job))]
            if extracted_insights:
                await store.persist_region_insights(
                    job,
                    extracted_insights,
                    evidence_pool,
                )
        await store.persist_candidates(job, admitted)
        await redis.set(f"discovery:refresh:{job.dedupe_key}", "completed", ex=CACHE_TTL)
        await store.record_refresh(job, "completed")
    except (BrokerFailure, RuntimeError) as error:
        print(
            "discovery job failed "
            f"region={job.region.region_id} mission={job.region.mission_type} "
            f"attempt={job.attempt} reason={type(error).__name__}",
            flush=True,
        )
        await retry_or_fail(redis, store, job)


CACHE_TTL = 600
CONSUMER_NAME = "discovery-worker-1"


async def handle_entry(
    redis: Redis,
    store: DiscoveryStore,
    broker: BrokerClient,
    crawler: PageCrawler | None,
    entry_id: str,
    values: dict[str, str],
) -> None:
    """ACK only after the job reached a bounded terminal/retry hand-off."""
    job = parse_job(values)
    if job is not None:
        await process_job(redis, store, broker, job, crawler)
    await redis.xack(REFRESH_STREAM, REFRESH_GROUP, entry_id)
    # ACK alone retains the coarse region reference indefinitely in a Stream.
    # Once retry/terminal state has been handed off, remove this processed entry.
    await redis.xdel(REFRESH_STREAM, entry_id)


async def reclaim_once(
    redis: Redis,
    store: DiscoveryStore,
    broker: BrokerClient,
    crawler: PageCrawler | None,
    start_id: str,
) -> str:
    """Recover a bounded page of crash-left messages and return its stream cursor."""
    reclaimed = await redis.xautoclaim(
        REFRESH_STREAM,
        REFRESH_GROUP,
        CONSUMER_NAME,
        min_idle_time=60_000,
        start_id=start_id,
        count=10,
    )
    # redis-py returns (next_start_id, [(id, values)], deleted_ids).
    next_start_id = str(reclaimed[0]) if reclaimed else "0-0"
    entries = reclaimed[1] if reclaimed and len(reclaimed) > 1 else []
    for entry_id, values in entries:
        await handle_entry(redis, store, broker, crawler, entry_id, values)
    return next_start_id


async def run() -> None:
    redis_url = os.getenv("REDIS_URL")
    if not redis_url:
        raise RuntimeError("REDIS_URL is required")
    client = Redis.from_url(redis_url, decode_responses=True)
    store = DiscoveryStore(os.getenv("DATABASE_URL"), None)
    broker = BrokerClient(os.getenv("DISCOVERY_BROKER_URL", "").rstrip("/"), os.getenv("DISCOVERY_WORKER_TOKEN", ""))
    crawler: PageCrawler | None = Crawl4AIPageCrawler(
        timeout_ms=int(os.getenv("DISCOVERY_CRAWLER_TIMEOUT_MS", "12000")),
    ) if _crawler_enabled() else None
    try:
        try:
            await client.xgroup_create(REFRESH_STREAM, REFRESH_GROUP, id="0", mkstream=True)
        except ResponseError as error:
            if "BUSYGROUP" not in str(error):
                raise
        reclaim_cursor = await reclaim_once(client, store, broker, crawler, "0-0")
        while True:
            await client.set(HEARTBEAT_KEY, "ok", ex=20)
            batches = await client.xreadgroup(
                REFRESH_GROUP,
                CONSUMER_NAME,
                {REFRESH_STREAM: ">"},
                count=1,
                block=5000,
            )
            if not batches:
                reclaim_cursor = await reclaim_once(client, store, broker, crawler, reclaim_cursor)
                continue
            _, entries = batches[0]
            entry_id, values = entries[0]
            await handle_entry(client, store, broker, crawler, entry_id, values)
    finally:
        await store.close()
        await client.aclose()


if __name__ == "__main__":
    asyncio.run(run())
