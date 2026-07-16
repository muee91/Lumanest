from datetime import datetime, timedelta, timezone

from app.models import HourlyForecastInput, RouteInput
from app.route_corridor import CorridorDegradation, build_opportunity_corridor


BASE = datetime(2026, 7, 17, 10, tzinfo=timezone.utc)


def route(*, samples=True) -> RouteInput:
    return RouteInput.model_validate({
        "mode": "driving",
        "stage": "planned",
        **({
            "routeId": "route_client_hash_123",
            "corridorSamples": [
                {
                    "latitude": 30.0 + index / 10,
                    "longitude": 120.0 + index / 10,
                    "system": "wgs84",
                    "expectedAt": BASE + timedelta(hours=index),
                    "progress": index / 2,
                }
                for index in range(3)
            ],
        } if samples else {}),
    })


def hourly(at, **overrides) -> HourlyForecastInput:
    return HourlyForecastInput.model_validate({
        "at": at,
        "condition": "clear",
        "cloudCoverPercent": 40,
        "windSpeedMps": 2,
        "precipitationMm": 0,
        "thunder": False,
        **overrides,
    })


def test_projects_bounded_forecast_and_solar_without_coordinates():
    result = build_opportunity_corridor(
        route(),
        [hourly(BASE + timedelta(hours=index)) for index in range(3)],
        opportunity_id="photo-sunsetglow-2026071710",
        geo_scope="regional",
    )

    assert result.degradation is None
    assert result.corridor is not None
    payload = result.corridor.model_dump(mode="json", by_alias=True)
    assert payload["routeId"] == "route_client_hash_123"
    assert len(payload["observations"]) == 3
    assert all(item["opportunityId"] == "photo-sunsetglow-2026071710" for item in payload["observations"])
    assert all("latitude" not in item and "longitude" not in item for item in payload["observations"])
    assert all(item["condition"] == "clear" for item in payload["observations"])


def test_missing_forecast_never_returns_partial_or_invented_corridor():
    no_forecast = build_opportunity_corridor(
        route(), [], opportunity_id="photo-sunsetglow-2026071710", geo_scope="regional"
    )
    assert no_forecast.corridor is None
    assert no_forecast.degradation == CorridorDegradation.HOURLY_FORECAST_UNAVAILABLE

    partial = build_opportunity_corridor(
        route(), [hourly(BASE)], opportunity_id="photo-sunsetglow-2026071710", geo_scope="regional"
    )
    assert partial.corridor is None
    assert partial.degradation == CorridorDegradation.HOURLY_FORECAST_COVERAGE_INSUFFICIENT


def test_point_opportunity_and_absent_samples_do_not_receive_corridor():
    point = build_opportunity_corridor(
        route(), [hourly(BASE + timedelta(hours=index)) for index in range(3)],
        opportunity_id="photo-bluehour-2026071710", geo_scope="point",
    )
    assert point.corridor is None
    assert point.degradation is None

    absent = build_opportunity_corridor(
        route(samples=False), [hourly(BASE)], opportunity_id="photo-sunsetglow-2026071710", geo_scope="regional"
    )
    assert absent.corridor is None
    assert absent.degradation == CorridorDegradation.NO_SAMPLES
