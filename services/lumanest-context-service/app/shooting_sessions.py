from __future__ import annotations

import hashlib
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from .models import (
    Coordinate,
    HourlyForecastInput,
    SceneType,
    ShootingSession,
    ShootingSessionFactor,
    ShootingSessionPhase,
    ShootingSessionTrendSample,
    ShootingTarget,
    SnapshotRequest,
)
from .solar import next_evening_window, next_morning_window, solar_state


EVENING_RULE_VERSION = "water-evening.1"
MORNING_RULE_VERSION = "water-morning.1"
GENERAL_SOLAR_RULE_VERSION = "general-solar.1"
CITY_AFTER_RAIN_RULE_VERSION = "city-after-rain.1"
ROUTE_LIGHT_RULE_VERSION = "route-light-window.1"
_ALIGNMENT = timedelta(minutes=90)


@dataclass(frozen=True)
class _ForecastPoint:
    at: datetime
    condition: str
    cloud: float | None
    wind: float
    precipitation: float
    visibility: float | None
    thunder: bool
    bracketed: bool


def build_general_morning_session(
    request: SnapshotRequest,
    scene: SceneType,
) -> ShootingSession | None:
    return _build_general_solar_session(request, scene, period="morning")


def build_general_evening_session(
    request: SnapshotRequest,
    scene: SceneType,
) -> ShootingSession | None:
    return _build_general_solar_session(request, scene, period="evening")


def build_city_after_rain_session(
    request: SnapshotRequest, scene: SceneType
) -> ShootingSession | None:
    """Create a short wet-street session only when rain is observed to end."""
    if scene is not SceneType.CITY or request.weather.stale or request.weather.thunder:
        return None
    timeline = _forecast_timeline(request)
    if len(timeline) < 2:
        return None
    current = request.weather.observed_at
    rain_end = None
    for left, right in zip(timeline, timeline[1:]):
        if left.at < current or left.precipitation_mm < 0.2:
            continue
        if (
            right.precipitation_mm <= 0.2
            and right.at <= current + timedelta(hours=3)
        ):
            rain_end = right.at
            break
    if rain_end is None:
        return None
    start_at = max(current, rain_end - timedelta(minutes=10))
    end_at = rain_end + timedelta(minutes=120)
    moments = [start_at, rain_end, rain_end + timedelta(minutes=30), end_at]
    points = [point for moment in moments if (point := _interpolate(moment, timeline))]
    if len(points) < 2 or any(point.thunder or point.wind >= 15 for point in points):
        return None
    phases = [
        ShootingSessionPhase(
            kind="rainEnding",
            startAt=start_at,
            peakAt=rain_end,
            endAt=rain_end + timedelta(minutes=20),
            conditionBand=_band(_weighted((_precipitation_score(points[1].precipitation), 55), (_general_wind_score(points[1].wind), 25), (_visibility_score(points[1].visibility or request.weather.visibility_km), 20))),
            directionDegrees=solar_state(request.coordinate, rain_end).azimuth_degrees,
        ),
        ShootingSessionPhase(
            kind="wetReflection",
            startAt=rain_end,
            peakAt=rain_end + timedelta(minutes=30),
            endAt=end_at,
            conditionBand=_band(_weighted((_precipitation_score(points[2].precipitation), 35), (_general_wind_score(points[2].wind), 35), (_visibility_score(points[2].visibility or request.weather.visibility_km), 30))),
            directionDegrees=solar_state(request.coordinate, rain_end + timedelta(minutes=30)).azimuth_degrees,
        ),
    ]
    score = 70 if request.weather.precipitation_mm > 0 else 55
    raw = "\0".join((CITY_AFTER_RAIN_RULE_VERSION, request.coordinate.latitude.__format__(".4f"), request.coordinate.longitude.__format__(".4f"), rain_end.isoformat()))
    identifier = hashlib.sha256(raw.encode()).hexdigest()[:24]
    samples = [
        ShootingSessionTrendSample(at=point.at, conditionIndex=_trend_index(point, point.visibility or request.weather.visibility_km), cloudCoverPercent=point.cloud, windSpeedMps=point.wind, precipitationMm=point.precipitation)
        for point in points
    ]
    return ShootingSession(
        id=f"session_{identifier}", kind="cityAfterRain", title="雨后城市窗口",
        startAt=start_at, endAt=end_at, primaryPhase="wetReflection",
        conditionBand=_band(score), confidenceBand=_confidence_band(request, points), trend="improving",
        phases=phases, factors=_factors("wetReflection", rain_end + timedelta(minutes=30), points, request.weather.visibility_km, request.forecast.observed_at),
        trendSamples=samples, targetCandidates=[], recommendedCapabilities=["tripod"],
        ruleVersion=CITY_AFTER_RAIN_RULE_VERSION, expiresAt=request.observed_at.astimezone(timezone.utc) + timedelta(minutes=15),
    )


def build_route_light_session(
    request: SnapshotRequest, scene: SceneType
) -> ShootingSession | None:
    """Build an observation-only light window from transient route samples.

    Corridor samples are deliberately not treated as reviewed stops. The
    resulting session has no target candidate and therefore cannot authorize
    a departure or navigation action.
    """
    if (
        request.weather.stale
        or request.route.mode == "none"
        or len(request.route.corridor_samples) < 2
    ):
        return None
    timeline = _forecast_timeline(request)
    candidates: list[tuple[datetime, _ForecastPoint, float]] = []
    for sample in request.route.corridor_samples:
        if not request.observed_at <= sample.expected_at <= request.observed_at + timedelta(hours=12):
            continue
        point = _interpolate(sample.expected_at, timeline)
        if point is None or point.thunder or point.wind >= 15:
            continue
        solar = solar_state(
            Coordinate(latitude=sample.latitude, longitude=sample.longitude),
            sample.expected_at,
        )
        elevation = solar.elevation_degrees or -90
        if -8 <= elevation <= 15:
            candidates.append((sample.expected_at, point, solar.azimuth_degrees))
    if len(candidates) < 2:
        return None
    candidates.sort(key=lambda item: item[0])
    first_at, first_point, first_direction = candidates[0]
    last_at, last_point, last_direction = candidates[-1]
    if last_at - first_at > timedelta(hours=3):
        last_at, last_point, last_direction = candidates[1]
    start_at = max(request.observed_at, first_at - timedelta(minutes=10))
    end_at = last_at + timedelta(minutes=20)
    midpoint = first_at + (last_at - first_at) / 2
    mid_point = _interpolate(midpoint, timeline) or first_point
    phases = [
        ShootingSessionPhase(
            kind="approach",
            startAt=start_at,
            peakAt=first_at,
            endAt=min(first_at + timedelta(minutes=10), end_at),
            conditionBand=_band(_route_score(first_point)),
            directionDegrees=first_direction,
        ),
        ShootingSessionPhase(
            kind="returnWindow",
            startAt=first_at,
            peakAt=midpoint,
            endAt=end_at,
            conditionBand=_band(_route_score(mid_point)),
            directionDegrees=last_direction,
        ),
    ]
    points = [first_point, mid_point, last_point]
    raw = "\0".join(
        (
            ROUTE_LIGHT_RULE_VERSION,
            request.route.route_id or "route",
            first_at.isoformat(),
            last_at.isoformat(),
        )
    )
    identifier = hashlib.sha256(raw.encode()).hexdigest()[:24]
    samples = [
        ShootingSessionTrendSample(
            at=point.at,
            conditionIndex=_route_score(point),
            cloudCoverPercent=point.cloud,
            windSpeedMps=point.wind,
            precipitationMm=point.precipitation,
        )
        for point in points
    ]
    delta = samples[-1].condition_index - samples[0].condition_index
    return ShootingSession(
        id=f"session_{identifier}",
        kind="routeLightWindow",
        title="沿途光线观察",
        startAt=start_at,
        endAt=end_at,
        primaryPhase="returnWindow",
        conditionBand=_band(max(item.condition_index for item in samples)),
        confidenceBand="medium" if all(point.bracketed for point in points) else "limited",
        trend="improving" if delta >= 10 else "weakening" if delta <= -10 else "stable",
        phases=phases,
        factors=_factors(
            "returnWindow",
            midpoint,
            points,
            request.weather.visibility_km,
            request.forecast.observed_at,
        ),
        trendSamples=samples,
        targetCandidates=[],
        recommendedCapabilities=["tripod"],
        ruleVersion=ROUTE_LIGHT_RULE_VERSION,
        expiresAt=request.observed_at.astimezone(timezone.utc) + timedelta(minutes=15),
    )


def _route_score(point: _ForecastPoint) -> int:
    return _weighted(
        (_cloud_score(point.cloud), 25),
        (_precipitation_score(point.precipitation), 25),
        (_general_wind_score(point.wind), 25),
        (_visibility_score(point.visibility or 10), 25),
    )


def _build_general_solar_session(
    request: SnapshotRequest,
    scene: SceneType,
    *,
    period: str,
) -> ShootingSession | None:
    """Build a truthful solar session without claiming a specific viewpoint.

    This is the baseline detail-page contract for non-water scenes. It only
    describes deterministic light phases and weather evidence. With no
    reviewed target the client remains in observation mode and never offers a
    route or departure instruction.
    """
    if request.weather.stale or any(
        warning.severity == "critical" and warning.expires_at > request.observed_at
        for warning in request.official_warnings
    ):
        return None

    morning = period == "morning"
    if morning:
        window = next_morning_window(request.coordinate, request.observed_at)
        if window is None:
            return None
        blue_peak_at = window.blue_hour_start + (
            window.blue_hour_end - window.blue_hour_start
        ) / 2
        session_start = window.blue_hour_start
        session_end = window.sunrise + timedelta(minutes=45)
        phase_specs = (
            (
                "morningBlueHour",
                window.blue_hour_start,
                blue_peak_at,
                window.blue_hour_end,
            ),
            ("sunrise", window.blue_hour_end, window.sunrise, session_end),
        )
        anchor = window.sunrise
    else:
        window = next_evening_window(request.coordinate, request.observed_at)
        if window is None:
            return None
        blue_peak_at = window.blue_hour_start + (
            window.blue_hour_end - window.blue_hour_start
        ) / 2
        session_start = window.sunset - timedelta(minutes=45)
        session_end = window.blue_hour_end
        phase_specs = (
            ("sunset", session_start, window.sunset, window.blue_hour_start),
            (
                "blueHour",
                window.blue_hour_start,
                blue_peak_at,
                window.blue_hour_end,
            ),
        )
        anchor = window.sunset

    if session_end > request.observed_at + timedelta(hours=24):
        return None
    hourly = _forecast_timeline(request)
    sample_moments = sorted(
        {
            moment
            for _, start_at, peak_at, end_at in phase_specs
            for moment in (start_at, peak_at, end_at)
        }
    )
    points = [
        point
        for moment in sample_moments
        if (point := _interpolate(moment, hourly)) is not None
    ]
    if len(points) < 2 or any(
        point.thunder or point.precipitation >= 5 or point.wind >= 15
        for point in points
    ):
        return None

    phases: list[tuple[ShootingSessionPhase, int]] = []
    for phase_kind, start_at, peak_at, end_at in phase_specs:
        point = _interpolate(peak_at, hourly)
        if point is None:
            continue
        visibility = (
            point.visibility
            if point.visibility is not None
            else request.weather.visibility_km
        )
        score = _weighted(
            (_cloud_score(point.cloud), 35),
            (_precipitation_score(point.precipitation), 30),
            (_visibility_score(visibility), 20),
            (_general_wind_score(point.wind), 15),
        )
        phases.append(
            (
                ShootingSessionPhase(
                    kind=phase_kind,
                    startAt=start_at,
                    peakAt=peak_at,
                    endAt=end_at,
                    conditionBand=_band(score),
                    directionDegrees=solar_state(
                        request.coordinate, peak_at
                    ).azimuth_degrees,
                ),
                score,
            )
        )
    if not phases:
        return None

    kind, title = _general_identity(scene, morning=morning)
    primary_phase, primary_score = max(phases, key=lambda item: item[1])
    samples = [
        ShootingSessionTrendSample(
            at=point.at,
            conditionIndex=_trend_index(
                point,
                point.visibility
                if point.visibility is not None
                else request.weather.visibility_km,
            ),
            cloudCoverPercent=point.cloud,
            windSpeedMps=point.wind,
            precipitationMm=point.precipitation,
        )
        for point in points
    ]
    delta = samples[-1].condition_index - samples[0].condition_index
    trend = "improving" if delta >= 10 else "weakening" if delta <= -10 else "stable"
    raw_id = "\0".join(
        (
            GENERAL_SOLAR_RULE_VERSION,
            kind,
            request.coordinate.latitude.__format__(".4f"),
            request.coordinate.longitude.__format__(".4f"),
            anchor.astimezone(timezone.utc).isoformat(),
        )
    )
    identifier = hashlib.sha256(raw_id.encode("utf-8")).hexdigest()[:24]
    return ShootingSession(
        id=f"session_{identifier}",
        kind=kind,
        title=title,
        startAt=session_start,
        endAt=session_end,
        primaryPhase=primary_phase.kind,
        conditionBand=_band(primary_score),
        confidenceBand=_confidence_band(request, points),
        trend=trend,
        phases=[phase for phase, _ in phases],
        factors=_factors(
            primary_phase.kind,
            primary_phase.peak_at,
            points,
            request.weather.visibility_km,
            request.forecast.observed_at,
        ),
        trendSamples=samples,
        targetCandidates=[],
        recommendedCapabilities=["tripod"],
        ruleVersion=GENERAL_SOLAR_RULE_VERSION,
        expiresAt=request.observed_at.astimezone(timezone.utc)
        + timedelta(minutes=20),
    )


def _general_identity(scene: SceneType, *, morning: bool) -> tuple[str, str]:
    if morning:
        return {
            SceneType.MOUNTAIN: ("mountainMorning", "山地晨光窗口"),
            SceneType.DESERT: ("desertSideLight", "荒漠晨间侧光窗口"),
            SceneType.VILLAGE: ("generalMorning", "村落晨光窗口"),
            SceneType.CITY: ("generalMorning", "城市晨光窗口"),
        }.get(scene, ("generalMorning", "晨间光线窗口"))
    return {
        SceneType.MOUNTAIN: ("mountainEvening", "山地晚光窗口"),
        SceneType.DESERT: ("desertSideLight", "荒漠晚间侧光窗口"),
        SceneType.VILLAGE: ("generalEvening", "村落晚光窗口"),
        SceneType.CITY: ("cityBlueHour", "城市日落与蓝调窗口"),
    }.get(scene, ("generalEvening", "日落与蓝调窗口"))


def build_water_morning_session(
    request: SnapshotRequest,
    scene: SceneType,
    targets: list[ShootingTarget] | None = None,
) -> ShootingSession | None:
    """Build a sunrise, morning blue-hour and optional reflection session."""
    eligible_targets = [
        target
        for target in (targets or [])
        if "waterMorning" in target.supported_sessions
    ]
    if (
        request.weather.stale
        or (scene is not SceneType.LAKE and not eligible_targets)
        or any(
            warning.severity == "critical"
            and warning.expires_at > request.observed_at
            for warning in request.official_warnings
        )
    ):
        return None
    solar_window = next_morning_window(request.coordinate, request.observed_at)
    if solar_window is None:
        return None
    session_end = solar_window.sunrise + timedelta(minutes=45)
    if session_end > request.observed_at + timedelta(hours=24):
        return None
    blue_peak_at = solar_window.blue_hour_start + (
        solar_window.blue_hour_end - solar_window.blue_hour_start
    ) / 2
    hourly = _forecast_timeline(request)
    moments = [
        solar_window.blue_hour_start,
        blue_peak_at,
        solar_window.blue_hour_end,
        solar_window.sunrise,
        session_end,
    ]
    points = [
        point
        for moment in moments
        if (point := _interpolate(moment, hourly)) is not None
    ]
    if len(points) < 2 or any(
        point.thunder or point.precipitation >= 5 or point.wind >= 15
        for point in points
    ):
        return None
    blue_point = _required_interpolation(blue_peak_at, hourly)
    sunrise_point = _required_interpolation(solar_window.sunrise, hourly)
    if blue_point is None or sunrise_point is None:
        return None
    blue_visibility = (
        blue_point.visibility
        if blue_point.visibility is not None
        else request.weather.visibility_km
    )
    sunrise_visibility = (
        sunrise_point.visibility
        if sunrise_point.visibility is not None
        else request.weather.visibility_km
    )
    blue_score = _weighted(
        (_precipitation_score(blue_point.precipitation), 35),
        (_visibility_score(blue_visibility), 30),
        (_cloud_score(blue_point.cloud), 20),
        (_general_wind_score(blue_point.wind), 15),
    )
    sunrise_score = _weighted(
        (_cloud_score(sunrise_point.cloud), 40),
        (_precipitation_score(sunrise_point.precipitation), 25),
        (_visibility_score(sunrise_visibility), 20),
        (_general_wind_score(sunrise_point.wind), 15),
    )
    phases: list[tuple[ShootingSessionPhase, int]] = [
        (
            ShootingSessionPhase(
                kind="morningBlueHour",
                startAt=solar_window.blue_hour_start,
                peakAt=blue_peak_at,
                endAt=solar_window.blue_hour_end,
                conditionBand=_band(blue_score),
                directionDegrees=solar_state(
                    request.coordinate, blue_peak_at
                ).azimuth_degrees,
            ),
            blue_score,
        ),
        (
            ShootingSessionPhase(
                kind="sunrise",
                startAt=solar_window.blue_hour_end,
                peakAt=solar_window.sunrise,
                endAt=session_end,
                conditionBand=_band(sunrise_score),
                directionDegrees=solar_state(
                    request.coordinate, solar_window.sunrise
                ).azimuth_degrees,
            ),
            sunrise_score,
        ),
    ]
    reflection_candidates = [
        point
        for point in points
        if solar_window.sunrise - timedelta(minutes=20)
        <= point.at
        <= solar_window.sunrise + timedelta(minutes=30)
    ]
    if reflection_candidates:
        reflection = min(
            reflection_candidates,
            key=lambda item: (item.wind, item.precipitation, item.at),
        )
        if reflection.wind <= 4 and reflection.precipitation == 0:
            reflection_score = _weighted(
                (_reflection_wind_score(reflection.wind), 60),
                (_precipitation_score(reflection.precipitation), 25),
                (
                    _visibility_score(
                        reflection.visibility
                        if reflection.visibility is not None
                        else request.weather.visibility_km
                    ),
                    15,
                ),
            )
            phases.append(
                (
                    ShootingSessionPhase(
                        kind="reflection",
                        startAt=max(
                            solar_window.blue_hour_end,
                            reflection.at - timedelta(minutes=20),
                        ),
                        peakAt=reflection.at,
                        endAt=min(
                            session_end,
                            reflection.at + timedelta(minutes=30),
                        ),
                        conditionBand=_band(reflection_score),
                        directionDegrees=solar_state(
                            request.coordinate, reflection.at
                        ).azimuth_degrees,
                    ),
                    reflection_score,
                )
            )
    phases.sort(key=lambda item: item[0].start_at)
    primary_phase, primary_score = max(phases, key=lambda item: item[1])
    confidence = _confidence_band(request, points)
    samples = [
        ShootingSessionTrendSample(
            at=point.at,
            conditionIndex=_trend_index(
                point,
                point.visibility
                if point.visibility is not None
                else request.weather.visibility_km,
            ),
            cloudCoverPercent=point.cloud,
            windSpeedMps=point.wind,
            precipitationMm=point.precipitation,
        )
        for point in points
    ]
    delta = samples[-1].condition_index - samples[0].condition_index
    trend = "improving" if delta >= 10 else "weakening" if delta <= -10 else "stable"
    factors = _factors(
        primary_phase.kind,
        primary_phase.peak_at,
        points,
        request.weather.visibility_km,
        request.forecast.observed_at,
    )
    raw_id = "\0".join(
        (
            MORNING_RULE_VERSION,
            request.coordinate.latitude.__format__(".4f"),
            request.coordinate.longitude.__format__(".4f"),
            solar_window.sunrise.astimezone(timezone.utc).isoformat(),
        )
    )
    identifier = hashlib.sha256(raw_id.encode("utf-8")).hexdigest()[:24]
    return ShootingSession(
        id=f"session_{identifier}",
        kind="waterMorning",
        title="湖岸晨光窗口",
        startAt=min(phase.start_at for phase, _ in phases),
        endAt=max(phase.end_at for phase, _ in phases),
        primaryPhase=primary_phase.kind,
        conditionBand=_band(primary_score),
        confidenceBand=confidence,
        trend=trend,
        phases=[phase for phase, _ in phases],
        factors=factors,
        trendSamples=samples,
        targetCandidates=eligible_targets[:3],
        recommendedCapabilities=["tripod"],
        ruleVersion=MORNING_RULE_VERSION,
        expiresAt=request.observed_at.astimezone(timezone.utc) + timedelta(minutes=20),
    )


def build_water_evening_session(
    request: SnapshotRequest,
    scene: SceneType,
    targets: list[ShootingTarget] | None = None,
) -> ShootingSession | None:
    """Build one explainable water-evening session from fresh facts.

    The returned condition index is a ranking aid and chart input, not a
    probability. Public copy must use the qualitative bands and evidence.
    """
    targets = [
        target
        for target in (targets or [])
        if "waterEvening" in target.supported_sessions
    ]
    if (
        request.weather.stale
        or (scene is not SceneType.LAKE and not targets)
        or any(
            warning.severity == "critical"
            and warning.expires_at > request.observed_at
            for warning in request.official_warnings
        )
    ):
        return None
    solar_window = next_evening_window(request.coordinate, request.observed_at)
    if solar_window is None:
        return None
    if solar_window.blue_hour_end > request.observed_at + timedelta(hours=24):
        return None

    moments = _sample_moments(
        solar_window.sunset,
        solar_window.blue_hour_start,
        solar_window.blue_hour_end,
    )
    hourly = _forecast_timeline(request)
    points = [
        point
        for moment in moments
        if (point := _interpolate(moment, hourly)) is not None
    ]
    if len(points) < 2:
        return None
    if any(
        point.thunder or point.precipitation >= 5 or point.wind >= 15
        for point in points
    ):
        return None

    sunset_point = _required_interpolation(solar_window.sunset, hourly)
    blue_peak_at = solar_window.blue_hour_start + (
        solar_window.blue_hour_end - solar_window.blue_hour_start
    ) / 2
    blue_point = _required_interpolation(blue_peak_at, hourly)
    if sunset_point is None or blue_point is None:
        return None

    sunset_visibility = (
        sunset_point.visibility
        if sunset_point.visibility is not None
        else request.weather.visibility_km
    )
    blue_visibility = (
        blue_point.visibility
        if blue_point.visibility is not None
        else request.weather.visibility_km
    )
    sunset_score = _weighted(
        (_cloud_score(sunset_point.cloud), 45),
        (_precipitation_score(sunset_point.precipitation), 25),
        (_visibility_score(sunset_visibility), 20),
        (_general_wind_score(sunset_point.wind), 10),
    )
    blue_score = _weighted(
        (_precipitation_score(blue_point.precipitation), 35),
        (_visibility_score(blue_visibility), 30),
        (_cloud_score(blue_point.cloud), 20),
        (_general_wind_score(blue_point.wind), 15),
    )

    phases: list[tuple[ShootingSessionPhase, int]] = [
        (
            ShootingSessionPhase(
                kind="sunset",
                startAt=solar_window.sunset - timedelta(minutes=45),
                peakAt=solar_window.sunset,
                endAt=solar_window.blue_hour_start,
                conditionBand=_band(sunset_score),
                directionDegrees=solar_state(
                    request.coordinate, solar_window.sunset
                ).azimuth_degrees,
            ),
            sunset_score,
        ),
        (
            ShootingSessionPhase(
                kind="blueHour",
                startAt=solar_window.blue_hour_start,
                peakAt=blue_peak_at,
                endAt=solar_window.blue_hour_end,
                conditionBand=_band(blue_score),
                directionDegrees=solar_state(
                    request.coordinate, blue_peak_at
                ).azimuth_degrees,
            ),
            blue_score,
        ),
    ]

    reflection_candidates = [
        point
        for point in points
        if solar_window.sunset - timedelta(minutes=30)
        <= point.at
        <= solar_window.blue_hour_end
    ]
    reflection = min(
        reflection_candidates,
        key=lambda item: (item.wind, item.precipitation, item.at),
    )
    if reflection.wind <= 4 and reflection.precipitation == 0:
        reflection_score = _weighted(
            (_reflection_wind_score(reflection.wind), 60),
            (_precipitation_score(reflection.precipitation), 25),
            (
                _visibility_score(
                    reflection.visibility
                    if reflection.visibility is not None
                    else request.weather.visibility_km
                ),
                15,
            ),
        )
        phases.append(
            (
                ShootingSessionPhase(
                    kind="reflection",
                    startAt=max(
                        solar_window.sunset - timedelta(minutes=30),
                        reflection.at - timedelta(minutes=20),
                    ),
                    peakAt=reflection.at,
                    endAt=min(
                        solar_window.blue_hour_end,
                        reflection.at + timedelta(minutes=30),
                    ),
                    conditionBand=_band(reflection_score),
                    directionDegrees=solar_state(
                        request.coordinate, reflection.at
                    ).azimuth_degrees,
                ),
                reflection_score,
            )
        )

    phases.sort(key=lambda item: item[0].start_at)
    primary_phase, primary_score = max(phases, key=lambda item: item[1])
    confidence = _confidence_band(request, points)
    samples = [
        ShootingSessionTrendSample(
            at=point.at,
            conditionIndex=_trend_index(
                point,
                point.visibility
                if point.visibility is not None
                else request.weather.visibility_km,
            ),
            cloudCoverPercent=point.cloud,
            windSpeedMps=point.wind,
            precipitationMm=point.precipitation,
        )
        for point in points
    ]
    delta = samples[-1].condition_index - samples[0].condition_index
    trend = "improving" if delta >= 10 else "weakening" if delta <= -10 else "stable"
    factors = _factors(
        primary_phase.kind,
        primary_phase.peak_at,
        points,
        request.weather.visibility_km,
        request.forecast.observed_at,
    )
    raw_id = "\0".join(
        (
            EVENING_RULE_VERSION,
            request.coordinate.latitude.__format__(".4f"),
            request.coordinate.longitude.__format__(".4f"),
            solar_window.sunset.astimezone(timezone.utc).isoformat(),
        )
    )
    identifier = hashlib.sha256(raw_id.encode("utf-8")).hexdigest()[:24]
    return ShootingSession(
        id=f"session_{identifier}",
        kind="waterEvening",
        title="湖岸晚间窗口",
        startAt=min(phase.start_at for phase, _ in phases),
        endAt=max(phase.end_at for phase, _ in phases),
        primaryPhase=primary_phase.kind,
        conditionBand=_band(primary_score),
        confidenceBand=confidence,
        trend=trend,
        phases=[phase for phase, _ in phases],
        factors=factors,
        trendSamples=samples,
        targetCandidates=targets[:3],
        recommendedCapabilities=["tripod"],
        ruleVersion=EVENING_RULE_VERSION,
        expiresAt=request.observed_at.astimezone(timezone.utc) + timedelta(minutes=20),
    )


def _sample_moments(
    sunset: datetime, blue_start: datetime, blue_end: datetime
) -> list[datetime]:
    return [
        sunset - timedelta(minutes=45),
        sunset,
        blue_start,
        blue_start + (blue_end - blue_start) / 2,
        blue_end,
    ]


def _required_interpolation(
    moment: datetime, hourly: list[HourlyForecastInput]
) -> _ForecastPoint | None:
    point = _interpolate(moment, hourly)
    return point if point is not None and point.bracketed else None


def _forecast_timeline(request: SnapshotRequest) -> list[HourlyForecastInput]:
    """Join a fresh current observation to the hourly forecast timeline.

    Providers commonly start their hourly series at the next whole hour. Near
    dawn or sunset that can leave a precision solar phase just before the
    first hourly point. The current observation is authoritative for that
    leading edge, so it may bracket the phase with the first forecast without
    pretending that an unbracketed hourly value is exact.
    """
    by_at = {item.at: item for item in request.forecast.hourly}
    if not request.weather.stale:
        by_at[request.weather.observed_at] = HourlyForecastInput(
            at=request.weather.observed_at,
            condition=request.weather.condition,
            cloudCoverPercent=request.weather.cloud_cover_percent,
            windSpeedMps=request.weather.wind_speed_mps,
            precipitationMm=request.weather.precipitation_mm,
            visibilityKm=request.weather.visibility_km,
            thunder=request.weather.thunder,
        )
    return sorted(by_at.values(), key=lambda item: item.at)


def _interpolate(
    moment: datetime, hourly: list[HourlyForecastInput]
) -> _ForecastPoint | None:
    ordered = sorted(hourly, key=lambda item: item.at)
    if not ordered:
        return None
    exact = next((item for item in ordered if item.at == moment), None)
    if exact is not None:
        return _from_hour(exact, moment, True)
    left = next((item for item in reversed(ordered) if item.at < moment), None)
    right = next((item for item in ordered if item.at > moment), None)
    if left is not None and right is not None:
        if moment - left.at <= _ALIGNMENT and right.at - moment <= _ALIGNMENT:
            span = (right.at - left.at).total_seconds()
            ratio = (moment - left.at).total_seconds() / span
            cloud = None
            if left.cloud_cover_percent is not None and right.cloud_cover_percent is not None:
                cloud = left.cloud_cover_percent + (
                    right.cloud_cover_percent - left.cloud_cover_percent
                ) * ratio
            nearest = left if ratio < .5 else right
            return _ForecastPoint(
                at=moment,
                condition=nearest.condition,
                cloud=cloud,
                wind=left.wind_speed_mps + (right.wind_speed_mps - left.wind_speed_mps) * ratio,
                precipitation=left.precipitation_mm
                + (right.precipitation_mm - left.precipitation_mm) * ratio,
                visibility=(
                    left.visibility_km
                    + (right.visibility_km - left.visibility_km) * ratio
                    if left.visibility_km is not None
                    and right.visibility_km is not None
                    else None
                ),
                thunder=left.thunder or right.thunder,
                bracketed=True,
            )
    nearest = min(ordered, key=lambda item: abs(item.at - moment))
    if abs(nearest.at - moment) <= timedelta(minutes=45):
        return _from_hour(nearest, moment, False)
    return None


def _from_hour(
    item: HourlyForecastInput, at: datetime, bracketed: bool
) -> _ForecastPoint:
    return _ForecastPoint(
        at=at,
        condition=item.condition,
        cloud=item.cloud_cover_percent,
        wind=item.wind_speed_mps,
        precipitation=item.precipitation_mm,
        visibility=item.visibility_km,
        thunder=item.thunder,
        bracketed=bracketed,
    )


def _weighted(*values: tuple[int, int]) -> int:
    total = sum(weight for _, weight in values)
    return round(sum(value * weight for value, weight in values) / total)


def _cloud_score(value: float | None) -> int:
    if value is None:
        return 50
    if 20 <= value <= 75:
        return 100
    if 10 <= value < 20 or 75 < value <= 90:
        return 60
    return 20


def _precipitation_score(value: float) -> int:
    return 100 if value == 0 else 60 if value <= 1 else 20


def _visibility_score(value: float) -> int:
    return 100 if value >= 10 else 60 if value >= 5 else 20


def _general_wind_score(value: float) -> int:
    return 100 if value <= 4 else 60 if value <= 8 else 20


def _reflection_wind_score(value: float) -> int:
    return 100 if value <= 2 else 60 if value <= 4 else 20


def _band(value: int) -> str:
    return "good" if value >= 70 else "fair" if value >= 45 else "limited"


def _confidence_band(request: SnapshotRequest, points: list[_ForecastPoint]) -> str:
    age = abs(request.observed_at - request.forecast.observed_at)
    if all(point.bracketed for point in points) and age <= timedelta(minutes=30):
        return "high"
    if (
        age <= timedelta(hours=3)
        and sum(point.bracketed for point in points) >= max(2, len(points) - 1)
    ):
        return "medium"
    return "limited"


def _trend_index(point: _ForecastPoint, visibility: float) -> int:
    return _weighted(
        (_cloud_score(point.cloud), 25),
        (_precipitation_score(point.precipitation), 30),
        (_general_wind_score(point.wind), 30),
        (_visibility_score(visibility), 15),
    )


def _factors(
    phase: str,
    phase_at: datetime,
    points: list[_ForecastPoint],
    visibility: float,
    source_at: datetime,
) -> list[ShootingSessionFactor]:
    point = min(points, key=lambda item: abs(item.at - phase_at))
    resolved_visibility = (
        point.visibility if point.visibility is not None else visibility
    )
    values = [
        ("cloud", "云量", f"{round(point.cloud)}%" if point.cloud is not None else "数据缺失", _cloud_score(point.cloud)),
        ("wind", "风速", f"{point.wind:.1f}m/s", _reflection_wind_score(point.wind) if phase == "reflection" else _general_wind_score(point.wind)),
        ("precipitation", "降水", f"{point.precipitation:.1f}mm", _precipitation_score(point.precipitation)),
        (
            "visibility",
            "能见度",
            f"{resolved_visibility:.0f}km",
            _visibility_score(resolved_visibility),
        ),
    ]
    if not all(item.bracketed for item in points):
        values.append(("dataCoverage", "数据覆盖", "部分时刻仅有邻近预报", 20))
    return [
        ShootingSessionFactor(
            id=identifier,
            effect="supporting" if score >= 70 else "neutral" if score >= 45 else "limiting",
            label=label,
            value=value,
            sourceAt=source_at,
        )
        for identifier, label, value, score in values
    ]
