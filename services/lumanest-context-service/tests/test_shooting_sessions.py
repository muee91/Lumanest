from datetime import datetime, timedelta, timezone

import pytest

from app.models import SceneType, SnapshotRequest
from app.shooting_sessions import (
    build_water_evening_session,
    build_water_morning_session,
)
from app.solar import next_evening_window, next_morning_window, solar_state


def request(
    *,
    thunder: bool = False,
    forecast_age_hours: int = 0,
    hourly_visibility_km: float = 20,
    critical_warning: bool = False,
    observed_at: datetime | None = None,
) -> SnapshotRequest:
    observed_at = observed_at or datetime(2026, 7, 14, 2, tzinfo=timezone.utc)
    hourly = [
        {
            "at": (observed_at + timedelta(hours=offset)).isoformat(),
            "condition": "cloudy",
            "cloudCoverPercent": 55,
            "windSpeedMps": 1.8,
            "precipitationMm": 0,
            "visibilityKm": hourly_visibility_km,
            "thunder": thunder,
        }
        for offset in range(24)
    ]
    return SnapshotRequest.model_validate(
        {
            "contractVersion": 4,
            "coordinate": {
                "latitude": 30.25,
                "longitude": 120.15,
                "system": "wgs84",
            },
            "observedAt": observed_at.isoformat(),
            "locale": "zh-CN",
            "intent": "photography",
            "route": {"mode": "none", "stage": "none"},
            "evidence": {"waterBody": True},
            "weather": {
                "observedAt": observed_at.isoformat(),
                "condition": "cloudy",
                "windSpeedMps": 1.8,
                "precipitationMm": 0,
                "visibilityKm": 20,
                "thunder": thunder,
                "stale": False,
            },
            "forecast": {
                "observedAt": (
                    observed_at - timedelta(hours=forecast_age_hours)
                ).isoformat(),
                "nextHourPrecipitationMm": 0,
                "nextThreeHoursMaxWindSpeedMps": 1.8,
                "thunderNextThreeHours": thunder,
                "hourly": hourly,
            },
            "officialWarnings": [
                {
                    "id": "a1b2c3d4e5f6",
                    "observedAt": observed_at.isoformat(),
                    "expiresAt": (observed_at + timedelta(hours=1)).isoformat(),
                    "severity": "critical",
                    "title": "雷电红色预警",
                }
            ]
            if critical_warning
            else [],
        }
    )


def test_solar_crossings_use_product_sunset_and_blue_hour_thresholds():
    body = request()
    window = next_evening_window(body.coordinate, body.observed_at)

    assert window is not None
    assert solar_state(body.coordinate, window.sunset).elevation_degrees == pytest.approx(
        -0.833, abs=0.2
    )
    assert solar_state(
        body.coordinate, window.blue_hour_start
    ).elevation_degrees == pytest.approx(-4, abs=0.2)
    assert solar_state(
        body.coordinate, window.blue_hour_end
    ).elevation_degrees == pytest.approx(-8, abs=0.2)
    assert window.sunset < window.blue_hour_start < window.blue_hour_end


def test_solar_crossings_use_product_sunrise_and_morning_blue_hour_thresholds():
    body = request()
    window = next_morning_window(body.coordinate, body.observed_at)

    assert window is not None
    assert solar_state(
        body.coordinate, window.blue_hour_start
    ).elevation_degrees == pytest.approx(-8, abs=0.2)
    assert solar_state(
        body.coordinate, window.blue_hour_end
    ).elevation_degrees == pytest.approx(-4, abs=0.2)
    assert solar_state(body.coordinate, window.sunrise).elevation_degrees == pytest.approx(
        -0.833, abs=0.2
    )
    assert window.blue_hour_start < window.blue_hour_end < window.sunrise


def test_water_morning_interpolates_forecast_and_explains_phases():
    body = request(forecast_age_hours=2)

    session = build_water_morning_session(body, SceneType.LAKE)

    assert session is not None
    assert session.kind == "waterMorning"
    assert {phase.kind for phase in session.phases}.issuperset(
        {"morningBlueHour", "sunrise"}
    )
    assert session.primary_phase in {
        "morningBlueHour", "sunrise", "reflection"
    }
    assert session.rule_version == "water-morning.1"
    assert session.recommended_capabilities == ["tripod"]
    assert all(sample.at.minute != 0 for sample in session.trend_samples)


def test_water_morning_uses_fresh_observation_before_first_hourly_point():
    seed = request(observed_at=datetime(2026, 7, 17, 19, tzinfo=timezone.utc))
    window = next_morning_window(seed.coordinate, seed.observed_at)
    assert window is not None
    observed_at = window.blue_hour_start - timedelta(minutes=10)
    body = request(observed_at=observed_at)
    first_hour = (observed_at + timedelta(hours=1)).replace(
        minute=0, second=0, microsecond=0
    )
    for index, item in enumerate(body.forecast.hourly):
        item.at = first_hour + timedelta(hours=index)

    assert body.forecast.hourly[0].at > window.blue_hour_start
    session = build_water_morning_session(body, SceneType.LAKE)

    assert session is not None
    assert session.kind == "waterMorning"
    assert {phase.kind for phase in session.phases}.issuperset(
        {"morningBlueHour", "sunrise"}
    )


def test_water_evening_interpolates_forecast_and_separates_confidence():
    body = request(forecast_age_hours=2)

    session = build_water_evening_session(body, SceneType.LAKE)

    assert session is not None
    assert session.condition_band == "good"
    assert session.confidence_band == "medium"
    assert {phase.kind for phase in session.phases} == {
        "sunset",
        "reflection",
        "blueHour",
    }
    assert session.primary_phase in {"sunset", "reflection", "blueHour"}
    assert session.rule_version == "water-evening.1"
    assert session.recommended_capabilities == ["tripod"]
    assert session.target_candidates == []
    assert all(sample.at.minute != 0 for sample in session.trend_samples)


def test_water_evening_uses_hourly_visibility_at_the_session_phase():
    body = request(hourly_visibility_km=2)

    session = build_water_evening_session(body, SceneType.LAKE)

    assert session is not None
    visibility = next(factor for factor in session.factors if factor.id == "visibility")
    assert visibility.value == "2km"
    assert visibility.effect == "limiting"


def test_water_evening_evidence_matches_the_primary_phase_peak():
    body = request()
    for item in body.forecast.hourly:
        item.wind_speed_mps = 5
        item.cloud_cover_percent = 55 if item.at.hour <= 11 else 100

    session = build_water_evening_session(body, SceneType.LAKE)

    assert session is not None
    assert session.primary_phase == "sunset"
    cloud = next(factor for factor in session.factors if factor.id == "cloud")
    assert cloud.value == "57%"


def test_water_evening_marks_old_forecast_confidence_as_limited():
    session = build_water_evening_session(
        request(forecast_age_hours=4), SceneType.LAKE
    )

    assert session is not None
    assert session.confidence_band == "limited"


def test_water_evening_hard_gate_withholds_unsafe_session():
    assert build_water_evening_session(request(thunder=True), SceneType.LAKE) is None


def test_water_evening_hard_gate_withholds_active_critical_warning():
    assert (
        build_water_evening_session(
            request(critical_warning=True), SceneType.LAKE
        )
        is None
    )


def test_water_evening_requires_lake_or_reviewed_target():
    assert build_water_evening_session(request(), SceneType.CITY) is None
