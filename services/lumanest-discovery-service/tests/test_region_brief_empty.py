from __future__ import annotations

import pytest

from app.models import RegionBriefRequest
from app.store import DiscoveryStore


def request() -> RegionBriefRequest:
    return RegionBriefRequest.model_validate({
        "contractVersion": 2,
        "snapshotId": "ctx_0123456789abcdef01234567",
        "activationType": "foreground_opportunistic",
        "locale": "zh-CN",
        "region": {"latitude": 30.509, "longitude": 120.689, "radiusMeters": 5000},
        "sceneProfile": {
            "physicalScene": "urban", "facets": [], "settlement": "urbanDistrict",
            "remoteness": "connected", "altitude": "low", "poiDensity": "dense",
            "mobility": "walking", "routeStage": "none",
        },
        "requestedSections": ["identity", "orientation", "photoThemes", "places"],
        "sourcePolicies": [{"id": "official-culture", "version": "2026-07", "qualityTier": "A"}],
    })


@pytest.mark.asyncio
async def test_completed_empty_missions_return_unavailable_instead_of_permanent_pending():
    class Redis:
        async def set(self, *_args, **_kwargs):
            # A terminal key already exists, so nothing new is queued.
            return False

        async def get(self, key):
            if key.startswith("discovery:refresh:"):
                return "empty"
            return None

    class Result:
        def mappings(self):
            return self

        def all(self):
            return []

    class Connection:
        async def execute(self, *_args, **_kwargs):
            return Result()

    class Context:
        async def __aenter__(self):
            return Connection()

        async def __aexit__(self, *_args):
            return None

    class Engine:
        def connect(self):
            return Context()

    store = DiscoveryStore(None, None)
    store.redis = Redis()
    store.engine = Engine()

    brief, status_code = await store.region_brief_for(request())

    assert status_code == 200
    assert brief.status == "unavailable"
    assert brief.refresh.retry_after_seconds is None
    assert brief.identity is None
    assert brief.insights == []
