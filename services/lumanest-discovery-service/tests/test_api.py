from __future__ import annotations

from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models import DiscoveryItem, DiscoveryRequest, DiscoveryResponse
from app.store import DiscoveryStore, REFRESH_STREAM


def payload() -> dict:
    return {
        "contractVersion": 1,
        "coordinate": {"latitude": 30.25, "longitude": 120.15, "system": "wgs84"},
        "locale": "zh-CN",
        "focus": "photography",
    }


def ready_response() -> DiscoveryResponse:
    return DiscoveryResponse.model_validate({
        "contractVersion": 1,
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
    assert captured["parameters"]["kinds"] == ["candidate_viewpoint"]


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
        async def set(self, key, value, ex, nx):
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
    assert values["longitude"] == "120.175"
    assert "30.25" not in str(values)
    assert "120.15" not in str(values)
    assert int(values["expiresAt"]) > 0
