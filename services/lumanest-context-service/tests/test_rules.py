from datetime import datetime, timezone

import pytest

from app.models import SnapshotRequest
from app.rules import evaluate


def request_for(*, evidence=None, route=None, condition="clear", day_phase="sunset", stale=False):
    return SnapshotRequest.model_validate({
        "contractVersion": 2,
        "coordinate": {"latitude": 30.25, "longitude": 120.15, "system": "wgs84"},
        "observedAt": "2026-07-14T10:00:00+08:00",
        "locale": "zh-CN",
        "intent": "photography",
        "route": route or {"mode": "none", "stage": "none"},
        "evidence": evidence or {},
        "weather": {
            "observedAt": "2026-07-14T10:00:00+08:00",
            "condition": condition,
            "windSpeedMps": 2,
            "precipitationMm": 0,
            "visibilityKm": 20,
            "thunder": False,
            "stale": stale,
        },
        "solar": {"dayPhase": day_phase},
    })


@pytest.mark.parametrize(
    ("evidence", "route", "scene"),
    [
        ({"urban": True}, None, "city"),
        ({"waterBody": True}, None, "lake"),
        ({"mountainous": True}, None, "mountain"),
        ({"aridLand": True}, None, "desert"),
        ({"settlement": True}, None, "village"),
        ({}, {"mode": "driving", "stage": "active"}, "driving"),
        ({}, {"mode": "hiking", "stage": "active"}, "hiking"),
    ],
)
def test_all_seven_scenes_are_selected_from_explicit_evidence(evidence, route, scene):
    assert evaluate(request_for(evidence=evidence, route=route)).scene == scene


def test_stale_weather_keeps_safety_but_drops_creative_events():
    body = request_for(evidence={"waterBody": True}, stale=True)
    body.weather.thunder = True
    result = evaluate(body)
    assert [event.id for event in result.events] == ["thunderstorm"]
    assert result.manifest.layout_mode == "safety"


def test_fingerprint_uses_a_grid_instead_of_exposing_coordinates():
    result = evaluate(request_for(evidence={"urban": True}, day_phase="blueHour"))
    assert "120.15" not in result.fingerprint
    assert result.context_id.startswith("ctx_")
