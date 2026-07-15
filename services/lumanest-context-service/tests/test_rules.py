from datetime import datetime, timezone

import pytest

from app.models import AstronomyEventsImport, SnapshotRequest
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
        "forecast": {
            "observedAt": "2026-07-14T10:00:00+08:00",
            "nextHourPrecipitationMm": 0,
            "nextThreeHoursMaxWindSpeedMps": 3,
            "thunderNextThreeHours": False,
        },
        "officialWarnings": [],
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
    assert result.data_freshness.context == "stale"
    assert result.allowed_actions == ["openSafety"]


def test_reviewed_wildlife_opportunity_is_creative_but_never_created_from_stale_weather():
    fresh = evaluate(request_for(evidence={"wildlifeOpportunity": True}))
    event = next(event for event in fresh.events if event.id == "regional-wildlife")
    assert event.channel == "wildlifeOpportunity"
    assert event.source == "wildlifeHistorical"
    assert event.geo_scope == "regional"
    assert fresh.manifest.primary_event_id == "regional-wildlife"

    stale = evaluate(request_for(evidence={"wildlifeOpportunity": True}, stale=True))
    assert all(event.id != "regional-wildlife" for event in stale.events)


def test_official_wildlife_risk_remains_a_safety_event_when_weather_is_stale():
    result = evaluate(request_for(evidence={"wildlifeSafety": True}, stale=True))
    event = next(event for event in result.events if event.id == "wildlife-area-risk")
    assert event.channel == "wildlifeSafety"
    assert event.source == "official"
    assert event.allowed_action == "openSafety"
    assert event.confidence == 1


def test_fingerprint_uses_a_grid_instead_of_exposing_coordinates():
    result = evaluate(request_for(evidence={"urban": True}, day_phase="blueHour"))
    assert "120.15" not in result.fingerprint
    assert result.context_id.startswith("ctx_")


def test_active_reviewed_astronomy_event_preserves_title_and_https_authority():
    starts_at = datetime(2026, 7, 14, 1, tzinfo=timezone.utc)
    ends_at = datetime(2026, 7, 14, 4, tzinfo=timezone.utc)
    result = evaluate(request_for(), astronomy_events=[{
        "external_id": "meteor-2026",
        "event_type": "meteorShower",
        "title": "英仙座流星雨极大期",
        "source_url": "https://science.nasa.gov/meteor-showers/",
        "starts_at": starts_at,
        "ends_at": ends_at,
    }])

    event = next(event for event in result.events if event.source == "astronomyCatalog")
    assert event.id.startswith("astronomy-")
    assert event.title == "英仙座流星雨极大期"
    assert str(event.source_url) == "https://science.nasa.gov/meteor-showers/"
    assert event.allowed_action == "openAuthority"
    assert event.observed_at == starts_at
    assert event.expires_at == ends_at
    assert result.manifest.primary_event_id == event.id
    assert "openAuthority" in result.allowed_actions


def test_astronomy_catalog_requires_traceable_https_source_and_ordered_times():
    valid = {
        "datasetType": "astronomyEvents",
        "source": {
            "id": "reviewed-astronomy",
            "enabled": False,
            "licenseStatus": "approved",
            "attribution": "NASA/JPL reviewed catalog",
            "version": "2026.07",
        },
        "events": [{
            "id": "meteor-2026",
            "eventType": "meteorShower",
            "startsAt": "2026-08-12T00:00:00Z",
            "endsAt": "2026-08-13T00:00:00Z",
            "title": "Reviewed meteor shower",
            "sourceUrl": "https://example.test/catalog/meteor-2026",
        }],
    }
    assert AstronomyEventsImport.model_validate(valid).events[0].id == "meteor-2026"

    invalid = valid | {
        "events": [valid["events"][0] | {
            "endsAt": "2026-08-11T00:00:00Z",
            "sourceUrl": "http://example.test/private",
        }]
    }
    with pytest.raises(ValueError):
        AstronomyEventsImport.model_validate(invalid)
