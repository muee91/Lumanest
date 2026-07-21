from __future__ import annotations

from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models import DiscoveryItem, DiscoveryRequest, DiscoveryResponse
from app.store import DiscoveryStore, REFRESH_STREAM, response_cache_seconds


def payload() -> dict:
    return {
        "activationType": "foreground_opportunistic",
        "missionType": "humanityEvents",
        "focus": "早市 夜市 展览",
        "locale": "zh-CN",
        "region": {"latitude": 30.25, "longitude": 120.15, "radiusMeters": 5000},
        "timeRange": {"startsAt": "2026-07-18T00:00:00Z", "endsAt": "2026-07-25T00:00:00Z"},
        "routeCorridor": None,
        "interests": ["humanityStreet"],
        "sourcePolicies": [{"id": "official-source", "version": "2026-07"}],
    }


def ready_response() -> DiscoveryResponse:
    return DiscoveryResponse.model_validate({
        "missionType": "humanityEvents",
        "status": "ready",
        "generatedAt": "2026-07-20T00:00:00Z",
        "expiresAt": "2026-07-20T00:10:00Z",
        "retryAfterSeconds": None,
        "items": [{
            "id": "place-a",
            "kind": "candidate_viewpoint",
            "title": "候选观景点",
            "subtitle": "有来源佐证",
            "placeStatus": "candidate",
            "coordinate": {"latitude": 30.25, "longitude": 120.15, "system": "wgs84"},
            "distanceMeters": 40,
            "address": None,
            "startsAt": None,
            "endsAt": None,
            "evidence": [{
                "publisher": "approved-source",
                "title": "公开目录记录",
                "url": "https://example.test/evidence/a",
                "observedAt": "2026-07-19T00:00:00Z",
            }],
        }],
    })


def test_health_is_public_and_internal_discovery_requires_its_own_token(monkeypatch):
    monkeypatch.setenv("DISCOVERY_INTERNAL_TOKEN", "discovery-test-token")
    with TestClient(app) as client:
        assert client.get("/healthz").json() == {"status": "ok"}
        assert client.post("/internal/v1/discover", json=payload()).status_code == 401


def test_readiness_returns_failure_status_when_storage_is_degraded(monkeypatch):
    async def degraded(_store):
        return {"postgres": False, "redis": True}

    monkeypatch.setattr(DiscoveryStore, "readiness", degraded)
    with TestClient(app) as client:
        response = client.get("/readyz")

    assert response.status_code == 503
    assert response.json() == {
        "status": "degraded",
        "dependencies": {"postgres": False, "redis": True},
    }


def test_internal_discovery_uses_fixed_contract_and_rejects_extra_fields(monkeypatch):
    monkeypatch.setenv("DISCOVERY_INTERNAL_TOKEN", "discovery-test-token")

    async def response_for(_store, _request):
        return ready_response(), 200

    monkeypatch.setattr(DiscoveryStore, "response_for", response_for)
    with TestClient(app) as client:
        response = client.post(
            "/internal/v1/discover",
            json=payload(),
            headers={"X-Internal-Service-Token": "discovery-test-token"},
        )
        assert response.status_code == 200
        assert response.json()["status"] == "ready"
        assert response.json()["items"][0]["evidence"][0]["title"] == "公开目录记录"

        invalid = payload() | {"deviceId": "never-accepted"}
        assert client.post(
            "/internal/v1/discover",
            json=invalid,
            headers={"X-Internal-Service-Token": "discovery-test-token"},
        ).status_code == 422


@pytest.mark.asyncio
async def test_pending_refresh_returns_retry_without_querying_storage():
    class FakeRedis:
        async def get(self, key):
            return "pending" if key.startswith("discovery:refresh:") else None

    store = DiscoveryStore(None, None)
    store.redis = FakeRedis()
    response, status_code = await store.response_for(DiscoveryRequest.model_validate(payload()))

    assert status_code == 202
    assert response.status == "pending"
    assert response.retry_after_seconds == 30
    assert response.items == []


@pytest.mark.asyncio
async def test_cached_response_is_reused_without_a_database_read():
    cached = ready_response()

    class FakeRedis:
        async def get(self, key):
            assert key.startswith("discovery:response:")
            return cached.model_dump_json(by_alias=True)

    store = DiscoveryStore(None, None)
    store.redis = FakeRedis()
    response, status_code = await store.response_for(DiscoveryRequest.model_validate(payload()))

    assert status_code == 200
    assert response == cached


@pytest.mark.asyncio
async def test_store_returns_only_approved_evidence_with_a_nonempty_title():
    captured = {}

    class Result:
        def mappings(self):
            return self

        def all(self):
            return [{
                "id": "place-a",
                "kind": "candidate_viewpoint",
                "name": "候选观景点",
                "summary": "有来源佐证",
                "verification": "candidate",
                "latitude": 30.25,
                "longitude": 120.15,
                "distance_meters": 40,
                "address": None,
                "starts_at": None,
                "ends_at": None,
                "provider": "approved-source",
                "evidence_title": "公开目录记录",
                "source_url": "https://example.test/evidence/a",
                "retrieved_at": datetime(2026, 7, 19, tzinfo=timezone.utc),
                "source_id": "official-source",
                "source_version": "2026-07",
            }]

    class Connection:
        async def execute(self, statement, parameters):
            captured["sql"] = str(statement)
            captured["parameters"] = parameters
            return Result()

    class ConnectionContext:
        async def __aenter__(self):
            return Connection()

        async def __aexit__(self, *_args):
            return None

    class Engine:
        def connect(self):
            return ConnectionContext()

    store = DiscoveryStore(None, None)
    store.engine = Engine()
    items = await store.candidates(DiscoveryRequest.model_validate(payload()))

    assert items[0].evidence[0].title == "公开目录记录"
    assert "review_status = 'approved'" in captured["sql"]
    assert "title IS NOT NULL" in captured["sql"]
    assert "evidence.retrieved_at, evidence.source_id" in captured["sql"]
    assert "evidence.retrieved_at, source_document.source_id" not in captured["sql"]
    assert captured["parameters"]["kinds"] == ["event"]


@pytest.mark.asyncio
async def test_removed_source_policy_revokes_existing_search_candidates_before_any_query():
    class Engine:
        def connect(self):
            raise AssertionError("revoked sources must not be queried or returned")

    request = payload()
    request["sourcePolicies"] = []
    store = DiscoveryStore(None, None)
    store.engine = Engine()

    assert await store.candidates(DiscoveryRequest.model_validate(request)) == []


def test_output_contract_caps_items_and_broker_text_limits():
    def maximum(model, name):
        return next(item.max_length for item in model.model_fields[name].metadata if hasattr(item, "max_length"))

    assert maximum(DiscoveryResponse, "items") == 40
    assert maximum(DiscoveryItem, "title") == 120
    assert maximum(DiscoveryItem, "subtitle") == 280
    assert maximum(DiscoveryItem, "address") == 200


@pytest.mark.asyncio
async def test_refresh_stream_uses_only_a_ttl_bound_coarse_region_not_client_coordinate_data():
    calls = []

    class FakeRedis:
        async def get(self, _key):
            return None

        async def set(self, key, value, ex, nx=None):
            calls.append(("set", key, value, ex, nx))
            return True

        async def xadd(self, stream, values, maxlen, approximate):
            calls.append(("xadd", stream, values, maxlen, approximate))

    store = DiscoveryStore(None, None)
    store.redis = FakeRedis()
    request = DiscoveryRequest.model_validate(payload())

    assert await store.schedule_refresh(request) is True
    values = calls[1][2]
    assert calls[1][0] == "xadd"
    assert calls[1][1] == REFRESH_STREAM
    assert values["regionId"].startswith("g")
    assert values["latitude"] == "30.275"
    assert values["activationType"] == "foreground_opportunistic"
    assert len(values["dedupeKey"]) == 64
    assert values["longitude"] == "120.175"
    assert "30.25" not in str(values)
    assert "120.15" not in str(values)
    assert int(values["expiresAt"]) > 0


@pytest.mark.asyncio
async def test_failed_stream_enqueue_clears_its_pending_dedupe_key():
    deleted = []

    class FakeRedis:
        async def set(self, *_args, **_kwargs):
            return True

        async def xadd(self, *_args, **_kwargs):
            raise RuntimeError("redis unavailable")

        async def get(self, key):
            return "pending" if key.startswith("discovery:refresh:") else None

        async def delete(self, key):
            deleted.append(key)

    store = DiscoveryStore(None, None)
    store.redis = FakeRedis()

    assert await store.schedule_refresh(DiscoveryRequest.model_validate(payload())) is False
    assert deleted and deleted[0].startswith("discovery:refresh:")


@pytest.mark.asyncio
async def test_foreground_activation_respects_mission_cooldown_without_enqueuing():
    calls = []

    class FakeRedis:
        async def get(self, key):
            return "queued" if key.startswith("discovery:cooldown:") else None

        async def set(self, *_args, **_kwargs):
            calls.append("set")
            return True

        async def xadd(self, *_args, **_kwargs):
            calls.append("xadd")

    store = DiscoveryStore(None, None)
    store.redis = FakeRedis()

    assert await store.schedule_refresh(DiscoveryRequest.model_validate(payload())) is False
    assert calls == []


def test_single_flight_key_ignores_focus_wording_within_the_same_region_and_bucket():
    first = DiscoveryRequest.model_validate(payload())
    second_payload = payload()
    second_payload["focus"] = "今天附近有什么活动"
    second = DiscoveryRequest.model_validate(second_payload)

    assert DiscoveryStore.fingerprint(first) != DiscoveryStore.fingerprint(second)
    assert DiscoveryStore.dedupe_key(first) == DiscoveryStore.dedupe_key(second)


def test_response_cache_fingerprint_uses_the_mission_refresh_bucket_not_each_open_timestamp():
    first = DiscoveryRequest.model_validate(payload())
    later_payload = payload()
    later_payload["timeRange"] = {
        "startsAt": "2026-07-18T01:30:00Z",
        "endsAt": "2026-07-25T01:30:00Z",
    }
    later = DiscoveryRequest.model_validate(later_payload)

    assert response_cache_seconds("humanityEvents") == 2 * 60 * 60
    assert DiscoveryStore.fingerprint(first) == DiscoveryStore.fingerprint(later)
