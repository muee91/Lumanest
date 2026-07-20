from datetime import datetime, timezone

from app.models import (
    ActivityState,
    PrimaryScene,
    SceneEvidence,
    SceneFacet,
    SnapshotRequest,
)
from app.rules import classify_scene_context


def _request(*, evidence: SceneEvidence, route: dict | None = None) -> SnapshotRequest:
    observed_at = datetime(2026, 7, 18, 10, tzinfo=timezone.utc)
    return SnapshotRequest.model_validate(
        {
            "contractVersion": 5,
            "coordinate": {"latitude": 30.25, "longitude": 120.15},
            "observedAt": observed_at,
            "route": route or {"mode": "none", "stage": "none"},
            "evidence": evidence.model_dump(mode="json", by_alias=True),
            "weather": {
                "observedAt": observed_at,
                "condition": "clear",
                "windSpeedMps": 1,
                "precipitationMm": 0,
                "visibilityKm": 20,
            },
            "forecast": {
                "observedAt": observed_at,
                "nextHourPrecipitationMm": 0,
                "thunderNextThreeHours": False,
            },
        }
    )


def test_activity_does_not_replace_physical_scene():
    request = _request(
        evidence=SceneEvidence(waterBody=True, sceneFacets=["lake"]),
        route={"mode": "driving", "stage": "active", "routeId": "route-1"},
    )

    context = classify_scene_context(request)

    assert context.primary_scene is PrimaryScene.INLAND_WATER
    assert context.activity is ActivityState.DRIVING
    assert context.facets == [SceneFacet.LAKE]


def test_reviewed_scene_has_fixed_100_point_override():
    request = _request(
        evidence=SceneEvidence(
            urban=True,
            reviewedPrimaryScene="village",
            sceneFacets=["skyline", "architecture"],
        )
    )

    context = classify_scene_context(request)

    assert context.primary_scene is PrimaryScene.VILLAGE
    assert context.scores == {PrimaryScene.VILLAGE: 100}
    assert context.reviewed_override is True


def test_empty_evidence_remains_unknown():
    context = classify_scene_context(_request(evidence=SceneEvidence()))

    assert context.primary_scene is PrimaryScene.UNKNOWN
    assert context.scores == {}
