from datetime import datetime, timedelta, timezone

import pytest

from app.models import AstronomyEventsImport, HourlyForecastInput, PhotographyTarget, SnapshotRequest
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


def test_v3_creates_only_fresh_bounded_forecast_opportunities():
    body = request_for(evidence={"waterBody": True})
    body.contract_version = 3
    body.forecast.hourly = [HourlyForecastInput.model_validate({
        "at": "2026-07-14T11:00:00+08:00", "condition": "clear", "cloudCoverPercent": 25,
        "windSpeedMps": 1.5, "precipitationMm": 0, "thunder": False,
    })]
    result = evaluate(body)
    assert result.contract_version == 3
    assert any(item.kind == "reflection" for item in result.opportunities)
    assert all(item.geo_scope in ("point", "regional", "route") for item in result.opportunities)
    assert all(item.start_at <= item.peak_at <= item.end_at for item in result.opportunities)
    assert all(item.primary_action in result.allowed_actions for item in result.opportunities)
    assert all(item.fallback_action in result.allowed_actions for item in result.opportunities if item.fallback_action)
    body.weather.stale = True
    assert evaluate(body).opportunities == []


def test_v3_embeds_only_transient_forecast_corridor_on_regional_opportunity():
    moments = [
        datetime(2026, 7, 14, 10 + offset, tzinfo=timezone(timedelta(hours=8)))
        for offset in range(3)
    ]
    body = request_for(route={
        "mode": "driving",
        "stage": "planned",
        "routeId": "client_route_hash_123",
        "corridorSamples": [
            {
                "latitude": 30.25 + index / 100,
                "longitude": 120.15 + index / 100,
                "system": "wgs84",
                "expectedAt": moment,
                "progress": index / 2,
            }
            for index, moment in enumerate(moments)
        ],
    })
    body.contract_version = 3
    body.forecast.hourly = [
        HourlyForecastInput.model_validate({
            "at": moment, "condition": "clear", "cloudCoverPercent": 25,
            "windSpeedMps": 1.5, "precipitationMm": 0, "thunder": False,
        })
        for moment in moments
    ]
    result = evaluate(body, astronomy_events=[{
        "external_id": "route-corridor-catalog",
        "starts_at": body.observed_at,
        "ends_at": body.observed_at + timedelta(hours=2),
        "title": "已审核天象",
        "source_url": "https://science.nasa.gov/",
    }])
    opportunity = next(item for item in result.opportunities if item.kind == "astronomy")
    assert opportunity.geo_scope == "regional"
    assert opportunity.corridor is not None
    assert opportunity.corridor.route_id == "client_route_hash_123"
    assert len(opportunity.corridor.observations) == 3
    assert all(item.opportunity_id == opportunity.id for item in opportunity.corridor.observations)
    payload = opportunity.corridor.model_dump(mode="json", by_alias=True)
    assert all("latitude" not in item and "longitude" not in item for item in payload["observations"])


def test_v3_binds_only_point_windows_to_a_reviewed_static_target():
    body = request_for(evidence={"waterBody": True})
    body.contract_version = 3
    body.forecast.hourly = [HourlyForecastInput.model_validate({
        "at": "2026-07-14T11:00:00+08:00", "condition": "clear", "cloudCoverPercent": 25,
        "windSpeedMps": 1.5, "precipitationMm": 0, "thunder": False,
    })]
    target = PhotographyTarget.model_validate({
        "id": "target_0123456789abcdef01234567", "name": "东岸观景台", "kind": "viewpoint",
        "coordinate": {"latitude": 30.251, "longitude": 120.151, "system": "wgs84"},
        "arrivalDeadline": "2026-07-14T10:00:00+08:00",
    })
    result = evaluate(body, target=target)
    reflection = next(item for item in result.opportunities if item.kind == "reflection")
    assert reflection.target is not None
    assert reflection.target.id == target.id
    assert reflection.target.coordinate.system == "wgs84"
    assert reflection.target.arrival_deadline == reflection.start_at


def test_v3_target_never_binds_regional_or_stale_windows():
    body = request_for(evidence={"mountainous": True})
    body.contract_version = 3
    body.forecast.hourly = [HourlyForecastInput.model_validate({
        "at": "2026-07-14T11:00:00+08:00", "condition": "clear", "cloudCoverPercent": 25,
        "windSpeedMps": 1.5, "precipitationMm": 0, "thunder": False,
    })]
    target = PhotographyTarget.model_validate({
        "id": "target_0123456789abcdef01234567", "name": "东岸观景台", "kind": "viewpoint",
        "coordinate": {"latitude": 30.251, "longitude": 120.151, "system": "wgs84"},
        "arrivalDeadline": "2026-07-14T10:00:00+08:00",
    })
    assert all(item.target is None for item in evaluate(body, target=target).opportunities if item.geo_scope != "point")
    body.weather.stale = True
    assert evaluate(body, target=target).opportunities == []


def test_v3_fingerprint_changes_when_hourly_opportunity_inputs_change():
    body = request_for(evidence={"waterBody": True})
    body.contract_version = 3
    body.forecast.hourly = [HourlyForecastInput.model_validate({
        "at": "2026-07-14T11:00:00+08:00", "condition": "clear", "cloudCoverPercent": 25,
        "windSpeedMps": 1.5, "precipitationMm": 0, "thunder": False,
    })]
    first = evaluate(body).fingerprint
    body.forecast.hourly[0].wind_speed_mps = 16
    assert evaluate(body).fingerprint != first


def test_v3_astronomy_window_never_outlives_catalog_event():
    body = request_for()
    body.contract_version = 3
    generated_at = body.observed_at.astimezone(timezone.utc)
    result = evaluate(body, astronomy_events=[{
        "external_id": "short-lived-event",
        "starts_at": generated_at - timedelta(minutes=5),
        "ends_at": generated_at + timedelta(minutes=5),
        "title": "短时天象窗口",
        "source_url": "https://example.test/short-lived-event",
    }])
    opportunity = next(item for item in result.opportunities if item.kind == "astronomy")
    assert opportunity.end_at == generated_at + timedelta(minutes=5)
    assert opportunity.peak_at <= opportunity.end_at


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
    assert event.allowed_action == "openWeather"
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
