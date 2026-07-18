from datetime import datetime, timedelta, timezone

import pytest

from app.models import (
    AstronomyEventsImport,
    HourlyForecastInput,
    OfficialWarningInput,
    PhotographyTarget,
    SnapshotRequest,
)
from app.rules import evaluate


def request_for(*, evidence=None, route=None, condition="clear", day_phase="sunset", stale=False):
    return SnapshotRequest.model_validate({
        "contractVersion": 4,
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
    ],
)
def test_physical_scenes_are_selected_from_explicit_evidence(evidence, route, scene):
    assert evaluate(request_for(evidence=evidence, route=route)).scene == scene


@pytest.mark.parametrize("activity", ["driving", "hiking"])
def test_activity_does_not_override_the_physical_scene(activity):
    result = evaluate(
        request_for(route={"mode": activity, "stage": "active"})
    )

    assert result.scene == "unknown"
    assert result.scene_context.activity == activity


def test_stale_weather_keeps_safety_but_drops_creative_events():
    body = request_for(evidence={"waterBody": True}, stale=True)
    body.weather.thunder = True
    result = evaluate(body)
    assert [event.id for event in result.events] == ["thunderstorm"]
    assert result.manifest.layout_mode == "safety"
    assert result.data_freshness.context == "stale"
    assert result.allowed_actions == ["openSafetyDetail"]


def test_fingerprint_changes_when_forecast_freshness_changes():
    body = request_for(evidence={"waterBody": True})
    first = evaluate(body).fingerprint

    body.forecast.observed_at -= timedelta(hours=4)

    assert evaluate(body).fingerprint != first


def test_fingerprint_changes_when_official_warning_state_changes():
    body = request_for(evidence={"waterBody": True})
    body.official_warnings = [
        OfficialWarningInput.model_validate(
            {
                "id": "a1b2c3d4e5f6",
                "observedAt": body.observed_at.isoformat(),
                "expiresAt": (body.observed_at + timedelta(hours=2)).isoformat(),
                "severity": "warning",
                "title": "雷电橙色预警",
            }
        )
    ]
    first = evaluate(body).fingerprint

    body.official_warnings[0].severity = "critical"
    upgraded = evaluate(body).fingerprint
    body.official_warnings[0].expires_at += timedelta(hours=1)

    assert upgraded != first
    assert evaluate(body).fingerprint != upgraded


def test_reviewed_wildlife_opportunity_is_creative_but_never_created_from_stale_weather():
    fresh = evaluate(request_for(evidence={"wildlifeOpportunity": True}))
    event = next(event for event in fresh.events if event.id == "regional-wildlife")
    assert event.channel == "wildlifeOpportunity"
    assert event.source == "wildlifeHistorical"
    assert event.geo_scope == "region"
    assert fresh.manifest.primary_event_id == "regional-wildlife"

    stale = evaluate(request_for(evidence={"wildlifeOpportunity": True}, stale=True))
    assert all(event.id != "regional-wildlife" for event in stale.events)


def test_official_wildlife_risk_remains_a_safety_event_when_weather_is_stale():
    result = evaluate(request_for(evidence={"wildlifeSafety": True}, stale=True))
    event = next(event for event in result.events if event.id == "wildlife-safety")
    assert event.channel == "wildlifeSafety"
    assert event.source == "official"
    assert event.allowed_action == "openSafetyDetail"
    assert event.confidence == 1


def test_fresh_unhealthy_air_is_rule_owned_safety_but_stale_aqi_is_not():
    body = request_for()
    body.weather.air_quality_index = 168
    body.weather.air_quality_category = "中度污染"
    body.weather.air_quality_observed_at = body.weather.observed_at
    body.weather.air_quality_stale = False
    result = evaluate(body)
    event = next(event for event in result.events if event.id == "unhealthy-air")
    assert event.channel == "safety"
    assert event.source == "weather"
    assert event.allowed_action == "openSafetyDetail"
    assert event.severity == "caution"

    body.weather.air_quality_stale = True
    stale = evaluate(body)
    assert all(event.id != "unhealthy-air" for event in stale.events)


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
    assert event.id == "event.astro.meteor_shower"
    assert event.title == "英仙座流星雨极大期"
    assert str(event.source_url) == "https://science.nasa.gov/meteor-showers/"
    assert event.allowed_action == "openAstronomyDetail"
    assert event.observed_at == starts_at
    assert event.expires_at == ends_at
    assert result.manifest.primary_event_id == event.id
    assert "openAstronomyDetail" in result.allowed_actions


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
