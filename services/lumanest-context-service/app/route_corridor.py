"""Bounded, transient route-corridor weather and solar alignment.

This code never looks up roads, terrain, obstructions, POIs, or route history.
It consumes only the client-provided, WGS84 corridor samples and the existing
hourly forecast in the current context request.  It returns no coordinates.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta, timezone
from enum import StrEnum

from .models import (
    Coordinate,
    HourlyForecastInput,
    PhotographyCorridor,
    PhotographyCorridorObservation,
    RouteInput,
)
from .solar import solar_state


class CorridorDegradation(StrEnum):
    NO_SAMPLES = "noSamples"
    HOURLY_FORECAST_UNAVAILABLE = "hourlyForecastUnavailable"
    HOURLY_FORECAST_COVERAGE_INSUFFICIENT = "hourlyForecastCoverageInsufficient"


@dataclass(frozen=True)
class CorridorBuild:
    """Internal result only; degradation is never represented as weather data."""

    corridor: PhotographyCorridor | None
    degradation: CorridorDegradation | None = None


_FORECAST_ALIGNMENT = timedelta(minutes=65)


def _aligned_forecast(expected_at, hourly: list[HourlyForecastInput]) -> HourlyForecastInput | None:
    if not hourly:
        return None
    candidate = min(
        hourly,
        key=lambda item: (
            abs(item.at.astimezone(timezone.utc) - expected_at.astimezone(timezone.utc)),
            item.at,
        ),
    )
    if abs(candidate.at.astimezone(timezone.utc) - expected_at.astimezone(timezone.utc)) > _FORECAST_ALIGNMENT:
        return None
    return candidate


def build_opportunity_corridor(
    route: RouteInput,
    hourly_forecast: list[HourlyForecastInput],
    *,
    opportunity_id: str,
    geo_scope: str,
) -> CorridorBuild:
    """Build an embedded opportunity corridor only when every input is present.

    A point opportunity is intentionally excluded.  A missing hourly record
    returns a degradation marker and no partial/guessed corridor, so the
    client cannot mistake a stale or incomplete forecast for a route fact.
    """
    if geo_scope not in ("region", "route"):
        return CorridorBuild(None)
    if not route.corridor_samples or route.route_id is None:
        return CorridorBuild(None, CorridorDegradation.NO_SAMPLES)
    if not hourly_forecast:
        return CorridorBuild(None, CorridorDegradation.HOURLY_FORECAST_UNAVAILABLE)

    observations: list[PhotographyCorridorObservation] = []
    for sample in route.corridor_samples:
        forecast = _aligned_forecast(sample.expected_at, hourly_forecast)
        if forecast is None:
            return CorridorBuild(None, CorridorDegradation.HOURLY_FORECAST_COVERAGE_INSUFFICIENT)
        solar = solar_state(
            Coordinate(latitude=sample.latitude, longitude=sample.longitude),
            sample.expected_at,
        )
        observations.append(PhotographyCorridorObservation(
            progress=sample.progress,
            expectedAt=sample.expected_at,
            condition=forecast.condition,
            cloudCoverPercent=forecast.cloud_cover_percent,
            windSpeedMps=forecast.wind_speed_mps,
            precipitationMm=forecast.precipitation_mm,
            thunder=forecast.thunder,
            sunAzimuthDegrees=solar.azimuth_degrees,
            opportunityId=opportunity_id,
        ))

    return CorridorBuild(PhotographyCorridor(
        routeId=route.route_id,
        observations=observations,
    ))
