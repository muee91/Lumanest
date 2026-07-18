from __future__ import annotations

import time

import pytest

from app.models import BrokerSearchResult, ExtractedCandidate
from app.store import RefreshJob, RegionReference
from app.worker import (
    BrokerClient,
    MAX_RETRIES,
    is_admissible,
    is_deterministic_admissible,
    parse_job,
    process_job,
)


def job(attempt: int = 0) -> RefreshJob:
    return RefreshJob(
        fingerprint="a" * 64,
        region=RegionReference(
            "g605:2402", 30.275, 120.125, "zh-cn",
            "humanityEvents", "早市 夜市 展览", 5000,
        ),
        expires_at=int(time.time()) + 600,
        attempt=attempt,
    )


def mission_job(mission_type: str) -> RefreshJob:
    value = job()
    return RefreshJob(
        value.fingerprint,
        RegionReference(
            value.region.region_id,
            value.region.latitude,
            value.region.longitude,
            value.region.locale,
            mission_type,
            "环湖路线" if mission_type == "routeConditions" else "博物馆",
            value.region.radius_meters,
        ),
        value.expires_at,
    )


def source() -> BrokerSearchResult:
    return BrokerSearchResult.model_validate({
        "sourceId": "official-tourism",
        "publisher": "Official tourism",
        "license": "CC-BY-4.0",
        "version": "2026-07",
        "title": "A documented viewpoint",
        "snippet": "Public visitor information. Coordinates: 30.280,120.130.",
        "url": "https://example.test/viewpoint",
        "publishedAt": "2026-07-20T00:00:00Z",
    })


def candidate(**overrides) -> ExtractedCandidate:
    value = {
        "kind": "candidate_viewpoint",
        "title": "候选观景点",
        "summary": "来源记录的拍摄方向。",
        "coordinate": {"latitude": 30.28, "longitude": 120.13},
        "coordinateEvidence": "30.280,120.130",
        "sourceIndexes": [0],
    }
    value.update(overrides)
    return ExtractedCandidate.model_validate(value)


def amap_source(source_id: str) -> BrokerSearchResult:
    return BrokerSearchResult.model_validate({
        "sourceId": source_id,
        "publisher": "高德地图",
        "license": "高德开放平台服务",
        "version": "amap-web-service-v1",
        "title": "高德结构化资料",
        "snippet": "当前资料。坐标：30.28000,120.13000",
        "url": "https://ditu.amap.com/",
        "publishedAt": "2026-07-20T00:00:00Z",
    })


def test_job_contains_only_expiring_grid_center_not_the_request_coordinate():
    values = job().stream_values()
    parsed = parse_job(values)

    assert parsed == job()
    assert values["latitude"] == "30.275"
    assert values["longitude"] == "120.125"
    assert "30.250" not in str(values)
    assert "120.150" not in str(values)
    assert int(values["expiresAt"]) > int(time.time())


def test_candidate_without_linked_https_evidence_is_not_admitted():
    assert is_admissible(candidate(sourceIndexes=[1]), [source()], job()) is None


def test_model_coordinate_without_exact_source_coordinate_text_is_not_admitted():
    assert is_admissible(candidate(coordinateEvidence="30.281,120.131"), [source()], job()) is None


def test_valid_vetted_evidence_admits_a_candidate_without_claiming_popularity():
    admitted = is_admissible(candidate(), [source()], job())

    assert admitted == [source()]
    assert candidate().kind == "candidate_viewpoint"
    assert "popular" not in candidate().title.lower()


def test_deterministic_missions_accept_only_the_matching_amap_product():
    route = candidate(kind="candidate_viewpoint", coordinateEvidence="30.28000,120.13000")
    opening = candidate(kind="attraction", coordinateEvidence="30.28000,120.13000")

    assert is_deterministic_admissible(
        route, [amap_source("amap-traffic")], mission_job("routeConditions")
    ) == [amap_source("amap-traffic")]
    assert is_deterministic_admissible(
        opening, [amap_source("amap-poi")], mission_job("openingAndClosure")
    ) == [amap_source("amap-poi")]
    assert is_deterministic_admissible(
        route, [amap_source("amap-poi")], mission_job("routeConditions")
    ) is None


@pytest.mark.asyncio
async def test_extraction_forwards_vetted_source_attribution_license_and_version(monkeypatch):
    captured = {}

    async def post(_self, _path, payload):
        captured["payload"] = payload
        return {"candidates": []}

    monkeypatch.setattr(BrokerClient, "_post", post)
    assert await BrokerClient("https://broker.test", "token").extract(job(), [source()]) == []

    forwarded = captured["payload"]["evidence"][0]
    assert forwarded["sourceId"] == "official-tourism"
    assert forwarded["publisher"] == "Official tourism"
    assert forwarded["license"] == "CC-BY-4.0"
    assert forwarded["version"] == "2026-07"


@pytest.mark.asyncio
async def test_broker_failure_has_a_bounded_retry_state_and_persists_no_item():
    class Redis:
        def __init__(self):
            self.sets = []
            self.added = []

        async def set(self, *args, **kwargs):
            self.sets.append((args, kwargs))

        async def xadd(self, *args, **kwargs):
            self.added.append((args, kwargs))

    class Store:
        def __init__(self):
            self.persisted = []
            self.states = []

        async def record_refresh(self, refresh_job, state):
            self.states.append((refresh_job, state))

        async def persist_candidates(self, refresh_job, candidates):
            self.persisted.extend(candidates)

    redis = Redis()
    store = Store()
    await process_job(redis, store, BrokerClient("", ""), job())

    assert store.persisted == []
    assert redis.added[0][0][1]["attempt"] == "1"
    assert redis.sets[0][0][1] == "retry:1"

    exhausted_redis = Redis()
    exhausted_store = Store()
    await process_job(exhausted_redis, exhausted_store, BrokerClient("", ""), job(MAX_RETRIES))

    assert exhausted_store.persisted == []
    assert exhausted_redis.added == []
    assert exhausted_redis.sets[0][0][1] == "failed"


@pytest.mark.asyncio
async def test_route_and_opening_jobs_use_deterministic_adapter_without_search_or_llm():
    class Redis:
        def __init__(self):
            self.sets = []

        async def set(self, *args, **kwargs):
            self.sets.append((args, kwargs))

    class Store:
        def __init__(self):
            self.persisted = []

        async def record_refresh(self, *_args):
            pass

        async def persist_candidates(self, _job, candidates):
            self.persisted.extend(candidates)

    class Broker:
        def __init__(self, mission_type):
            self.mission_type = mission_type
            self.search_called = False
            self.extract_called = False

        async def search(self, _job):
            self.search_called = True
            raise AssertionError("deterministic mission must not search Tavily")

        async def extract(self, _job, _evidence):
            self.extract_called = True
            raise AssertionError("deterministic mission must not call the LLM")

        async def deterministic(self, _job, evidence):
            assert evidence == []
            source_id = "amap-traffic" if self.mission_type == "routeConditions" else "amap-poi"
            kind = "candidate_viewpoint" if self.mission_type == "routeConditions" else "attraction"
            return [candidate(kind=kind, coordinateEvidence="30.28000,120.13000")], [amap_source(source_id)]

    for mission_type in ("routeConditions", "openingAndClosure"):
        redis = Redis()
        store = Store()
        broker = Broker(mission_type)
        await process_job(redis, store, broker, mission_job(mission_type))
        assert len(store.persisted) == 1
        assert broker.search_called is False
        assert broker.extract_called is False
        assert redis.sets[-1][0][1] == "completed"
