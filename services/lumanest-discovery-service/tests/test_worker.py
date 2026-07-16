from __future__ import annotations

import time

import pytest

from app.models import BrokerSearchResult, ExtractedCandidate
from app.store import RefreshJob, RegionReference
from app.worker import BrokerClient, MAX_RETRIES, is_admissible, parse_job, process_job


def job(attempt: int = 0) -> RefreshJob:
    return RefreshJob(
        fingerprint="a" * 64,
        region=RegionReference("g605:2402", 30.275, 120.125, "zh-cn", "photography"),
        expires_at=int(time.time()) + 600,
        attempt=attempt,
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
