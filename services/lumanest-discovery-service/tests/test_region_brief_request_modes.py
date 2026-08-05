from datetime import datetime, timezone

from app.models import RegionBriefRequest
from app.store import DiscoveryStore


def _request(*, activation_type: str, sections: list[str], radius_meters: int) -> RegionBriefRequest:
    return RegionBriefRequest.model_validate({
        "contractVersion": 2,
        "snapshotId": "ctx_0123456789abcdef01234567",
        "activationType": activation_type,
        "locale": "zh-CN",
        "region": {
            "latitude": 30.275,
            "longitude": 120.175,
            "radiusMeters": radius_meters,
        },
        "sceneProfile": {
            "physicalScene": "urban",
            "facets": ["architecture", "oldTown"],
            "settlement": "historicTown",
            "remoteness": "connected",
            "altitude": "low",
            "poiDensity": "normal",
            "mobility": "walking",
            "routeStage": "none",
        },
        "requestedSections": sections,
        "sourcePolicies": [{
            "id": "official-cultural-source",
            "version": "2026-08-05",
            "qualityTier": "A",
        }],
    })


def test_foreground_brief_schedules_only_core_missions() -> None:
    request = _request(
        activation_type="foreground_opportunistic",
        radius_meters=5_000,
        sections=["identity", "orientation", "photoThemes", "practical"],
    )

    assert DiscoveryStore._brief_missions(request) == [
        "localStories",
        "seasonalSignals",
        "openingAndClosure",
    ]


def test_manual_brief_schedules_all_expanded_missions() -> None:
    request = _request(
        activation_type="user_manual",
        radius_meters=15_000,
        sections=[
            "identity",
            "orientation",
            "photoThemes",
            "happeningNow",
            "places",
            "localTaste",
            "etiquette",
            "practical",
        ],
    )

    assert DiscoveryStore._brief_missions(request) == [
        "localStories",
        "seasonalSignals",
        "humanityEvents",
        "popularPlaces",
        "hiddenPlaces",
        "localFoodAndSpecialties",
        "culturalEtiquette",
        "openingAndClosure",
    ]


def test_activation_and_radius_reach_each_discovery_job() -> None:
    request = _request(
        activation_type="user_manual",
        radius_meters=35_000,
        sections=["happeningNow"],
    )

    job_request = DiscoveryStore._brief_discovery_request(
        request,
        "humanityEvents",
        datetime(2026, 8, 5, 3, tzinfo=timezone.utc),
    )

    assert job_request.activation_type == "user_manual"
    assert job_request.region.radius_meters == 35_000
    assert job_request.mission_type == "humanityEvents"
    assert job_request.source_policies[0].quality_tier == "A"
