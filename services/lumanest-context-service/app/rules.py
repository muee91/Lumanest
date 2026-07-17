from __future__ import annotations

import hashlib
import re
import math
from datetime import datetime, timedelta, timezone

from .models import (ContextEvent, Manifest, PhotographyOpportunity, PhotographyTarget, SceneEvidence,
                     SceneType, SnapshotRequest, SnapshotResponse, SnapshotResponseV3)
from .route_corridor import build_opportunity_corridor
from .solar import solar_state


_moon_reference = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)
_synodic_month_days = 29.53058867


def moon_state(moment: datetime) -> tuple[str, float]:
    age = ((moment.astimezone(timezone.utc) - _moon_reference).total_seconds() / 86_400) % _synodic_month_days
    illumination = (1 - math.cos(2 * math.pi * age / _synodic_month_days)) / 2
    phase_index = int(((age / _synodic_month_days) * 8) + 0.5) % 8
    phases = (
        "newMoon",
        "waxingCrescent",
        "firstQuarter",
        "waxingGibbous",
        "fullMoon",
        "waningGibbous",
        "lastQuarter",
        "waningCrescent",
    )
    return phases[phase_index], round(illumination, 4)


def classify_scene(request: SnapshotRequest, evidence: SceneEvidence | None = None) -> SceneType:
    facts = evidence or request.evidence
    if request.route.mode == "hiking" and request.route.stage == "active":
        return SceneType.HIKING
    if request.route.mode == "driving" and request.route.stage == "active":
        return SceneType.DRIVING
    if facts.water_body:
        return SceneType.LAKE
    if facts.mountainous:
        return SceneType.MOUNTAIN
    if facts.arid_land:
        return SceneType.DESERT
    if facts.settlement:
        return SceneType.VILLAGE
    if facts.urban:
        return SceneType.CITY
    return SceneType.UNKNOWN


def context_fingerprint(
    request: SnapshotRequest,
    scene: SceneType,
    evidence: SceneEvidence | None = None,
    astronomy_events: list[dict] | None = None,
    target: PhotographyTarget | None = None,
) -> str:
    facts = evidence or request.evidence
    solar = request.solar or solar_state(request.coordinate, request.observed_at)
    warning_ids = ",".join(sorted(warning.id for warning in request.official_warnings))
    forecast_state = ":".join((
        str(round(request.forecast.next_hour_precipitation_mm, 1)),
        str(round(request.forecast.next_three_hours_max_wind_speed_mps or 0, 1)),
        str(request.forecast.thunder_next_three_hours),
    ))
    # V3 opportunities are derived from the individual hourly records, rather
    # than the aggregate forecast above.  Keep their bounded, non-identifying
    # state in the fingerprint so a Redis hit cannot return a window generated
    # from an earlier hourly forecast.
    hourly_state = ",".join(sorted(
        ":".join((
            item.at.astimezone(timezone.utc).isoformat(timespec="minutes"),
            item.condition,
            str(round(item.cloud_cover_percent, 1)) if item.cloud_cover_percent is not None else "unknown",
            str(round(item.wind_speed_mps, 1)),
            str(round(item.precipitation_mm, 1)),
            str(item.thunder),
        ))
        for item in request.forecast.hourly
    ))
    air_state = f"{request.weather.air_quality_index}:{request.weather.air_quality_stale}"
    corridor_state = ",".join(
        ":".join((
            request.route.route_id or "",
            f"{sample.latitude:.4f}",
            f"{sample.longitude:.4f}",
            sample.expected_at.astimezone(timezone.utc).isoformat(timespec="minutes"),
            f"{sample.progress:.4f}",
        ))
        for sample in request.route.corridor_samples
    )
    grid = f"{request.coordinate.latitude:.2f},{request.coordinate.longitude:.2f}"
    raw = "|".join((
        str(request.contract_version),
        grid,
        scene.value,
        solar.day_phase,
        request.weather.condition,
        request.weather.observed_at.astimezone(timezone.utc).isoformat(timespec="minutes"),
        forecast_state,
        hourly_state,
        air_state,
        warning_ids,
        request.route.mode,
        request.route.stage,
        request.intent,
        str(facts.wildlife_opportunity),
        str(facts.wildlife_safety),
        ",".join(sorted(str(event.get("external_id", "")) for event in (astronomy_events or []))),
        target.id if target is not None else "",
        corridor_state,
    ))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def _opportunities(
    request: SnapshotRequest, scene: SceneType, solar, astronomy_events: list[dict], generated_at: datetime,
    target: PhotographyTarget | None = None,
) -> list[PhotographyOpportunity]:
    """Create bounded, deterministic creative windows from fresh forecast facts only."""
    if request.weather.stale:
        return []
    result: list[PhotographyOpportunity] = []

    def opportunity_id(kind: str, start: datetime) -> str:
        # Public contracts permit lower-case opaque IDs only. Rule kinds use
        # camelCase for their bounded enum values, so normalize them once
        # before they are reused by the corridor and response models.
        normalized = re.sub(r"[^a-z0-9_-]", "", kind.lower())
        return f"photo-{normalized}-{start.strftime('%Y%m%d%H')}"

    def add(kind: str, start: datetime, score: int, confidence: float, scope: str,
            primary: str, evidence: list[tuple[str, str]], direction: float | None = None,
            fallback: str | None = None, hints: list[str] | None = None,
            end: datetime | None = None) -> None:
        if len(result) >= 8 or start < generated_at or start > generated_at + timedelta(hours=6):
            return
        end = min(end or (start + timedelta(minutes=35)), start + timedelta(minutes=35))
        if end <= start:
            return
        peak = min(start + timedelta(minutes=15), end)
        bound_target = (
            target.model_copy(update={"arrival_deadline": start})
            if target is not None and scope == "point" else None
        )
        identifier = opportunity_id(kind, start)
        corridor = build_opportunity_corridor(
            request.route,
            request.forecast.hourly,
            opportunity_id=identifier,
            geo_scope=scope,
        ).corridor
        result.append(PhotographyOpportunity.model_validate({
            "id": identifier, "kind": kind,
            "startAt": start, "peakAt": peak, "endAt": end,
            "score": score, "confidence": confidence, "geoScope": scope,
            "directionDegrees": direction, "evidence": [{"label": label, "value": value} for label, value in evidence],
            "primaryAction": primary, "fallbackAction": fallback, "equipmentHints": hints or [],
            "target": bound_target,
            "corridor": corridor,
        }))

    # Use the current solar result and each QWeather hour; no model inference and no coordinates.
    hourly = request.forecast.hourly or []
    if not hourly:
        hourly = []
    for item in hourly:
        if item.thunder or item.precipitation_mm >= 5 or item.wind_speed_mps >= 15:
            continue
        hour_solar = solar_state(request.coordinate, item.at)
        cloud = item.cloud_cover_percent if item.cloud_cover_percent is not None else 50
        clear = item.condition in ("clear", "cloudy")
        base = [("预报", item.condition), ("云量", f"{round(cloud)}%")]
        if hour_solar.day_phase == "blueHour" and clear:
            add("blueHour", item.at, 82, .82, "point", "openShootingWindow", base, hour_solar.azimuth_degrees, "openExplore", ["广角镜头", "三脚架"])
        if hour_solar.day_phase == "sunset" and clear and 20 <= cloud <= 75:
            add("sunsetGlow", item.at, 78, .72, "regional", "openShootingWindow", base + [("时段", "日落前后")], hour_solar.azimuth_degrees, "openExplore", ["广角镜头"])
        if scene is SceneType.MOUNTAIN and hour_solar.day_phase in ("dawn", "sunset") and clear and cloud <= 60:
            add("alpenglow", item.at, 76, .70, "regional", "openShootingWindow", base, hour_solar.azimuth_degrees, "openExplore", ["长焦镜头", "三脚架"])
        if scene is SceneType.LAKE and item.wind_speed_mps <= 3 and item.precipitation_mm == 0 and clear:
            add("reflection", item.at, 74, .76, "point", "openExplore", base + [("风速", f"{item.wind_speed_mps:.1f}m/s")], None, "openShootingWindow", ["偏振镜"])
        if hour_solar.day_phase == "dawn" and item.condition in ("cloudy", "clear") and 65 <= cloud <= 100 and item.wind_speed_mps <= 4:
            add("morningMist", item.at, 65, .58, "regional", "openExplore", base + [("风速", f"{item.wind_speed_mps:.1f}m/s")], None, "openWeather", ["中长焦镜头"])

    for catalog in astronomy_events:
        starts, ends = catalog.get("starts_at"), catalog.get("ends_at")
        if not isinstance(starts, datetime) or not isinstance(ends, datetime):
            continue
        if ends <= generated_at or starts > generated_at + timedelta(hours=6):
            continue
        add("astronomy", max(starts, generated_at), 86, 1, "regional", "openAuthority",
            [("目录", "已审核天象")], None, None, ["三脚架", "广角镜头"], ends)
    return sorted(result, key=lambda item: (-item.score, item.start_at, item.id))


def evaluate(
    request: SnapshotRequest,
    evidence: SceneEvidence | None = None,
    astronomy_events: list[dict] | None = None,
    target: PhotographyTarget | None = None,
) -> SnapshotResponse | SnapshotResponseV3:
    generated_at = request.observed_at.astimezone(timezone.utc)
    expires_at = generated_at + timedelta(minutes=15)
    scene = classify_scene(request, evidence)
    facts = evidence or request.evidence
    fingerprint = context_fingerprint(request, scene, facts, astronomy_events, target)
    moon_phase, moon_illumination = moon_state(generated_at)
    solar = request.solar or solar_state(request.coordinate, generated_at)
    events: list[ContextEvent] = []

    def add(
        event_id: str,
        channel: str,
        source: str,
        confidence: float,
        action: str,
        severity: str = "info",
        geo_scope: str = "regional",
        observed_at: datetime | None = None,
        event_expires_at: datetime | None = None,
        title: str | None = None,
        source_url: str | None = None,
    ) -> None:
        events.append(ContextEvent.model_validate({
            "id": event_id,
            "channel": channel,
            "source": source,
            "observedAt": observed_at or request.weather.observed_at,
            "expiresAt": event_expires_at or expires_at,
            "confidence": confidence,
            "geoScope": geo_scope,
            "severity": severity,
            "allowedAction": action,
            "title": title,
            "sourceUrl": source_url,
        }))

    for catalog_event in astronomy_events or []:
        external_id = str(catalog_event.get("external_id", ""))
        event_hash = hashlib.sha256(external_id.encode("utf-8")).hexdigest()[:12]
        add(
            f"astronomy-{event_hash}",
            "opportunity",
            "astronomyCatalog",
            1,
            "openAuthority",
            "info",
            "regional",
            catalog_event["starts_at"],
            catalog_event["ends_at"],
            str(catalog_event["title"]),
            str(catalog_event["source_url"]),
        )

    if request.weather.thunder:
        add("thunderstorm", "safety", "weather", 1, "openSafety", "critical", "regional")
    if request.weather.wind_speed_mps >= 15:
        add("strong-wind", "safety", "weather", 0.9, "openSafety", "warning", "regional")
    if request.weather.precipitation_mm >= 10:
        add("heavy-rain", "safety", "weather", 0.9, "openSafety", "warning", "regional")
    if facts.wildlife_safety:
        add("wildlife-area-risk", "wildlifeSafety", "official", 1, "openSafety", "warning", "regional")
    if not request.weather.stale and not request.weather.air_quality_stale and \
            request.weather.air_quality_index is not None and request.weather.air_quality_index >= 150:
        severity = "critical" if request.weather.air_quality_index >= 300 else \
            "warning" if request.weather.air_quality_index >= 200 else "caution"
        add("unhealthy-air", "safety", "weather", 0.95, "openWeather", severity, "regional")

    for warning in request.official_warnings:
        if warning.expires_at <= generated_at:
            continue
        add(
            f"weather-warning-{warning.id}",
            "safety",
            "official",
            1,
            "openSafety",
            warning.severity,
            "regional",
            warning.observed_at,
            warning.expires_at,
            warning.title,
        )

    if not request.weather.stale:
        if facts.wildlife_opportunity:
            add("regional-wildlife", "wildlifeOpportunity", "wildlifeHistorical", 0.5, "openExplore", "info", "regional")
        if request.forecast.thunder_next_three_hours:
            add("thunderstorm-forecast", "safety", "weather", 0.9, "openSafety", "warning")
        if request.forecast.next_three_hours_max_wind_speed_mps is not None and \
                request.forecast.next_three_hours_max_wind_speed_mps >= 15:
            add("strong-wind-forecast", "safety", "weather", 0.8, "openSafety", "caution")
        if request.forecast.next_hour_precipitation_mm >= 5:
            add("rain-soon", "safety", "weather", 0.8, "openWeather", "caution")
        edge_light = solar.day_phase in ("dawn", "sunset")
        clear_enough = request.weather.condition in ("clear", "cloudy")
        if scene is SceneType.CITY and solar.day_phase == "blueHour":
            add("blue-hour", "opportunity", "solar", 0.9, "openShootingWindow", geo_scope="point")
        if scene is SceneType.LAKE and request.weather.wind_speed_mps <= 3 and request.weather.precipitation_mm == 0:
            add("reflection", "opportunity", "rule", 0.82, "openExplore", geo_scope="point")
        if scene is SceneType.MOUNTAIN and edge_light and clear_enough and request.weather.visibility_km >= 10:
            add("alpenglow", "opportunity", "rule", 0.72, "openShootingWindow", geo_scope="regional")
        if scene is SceneType.DESERT and request.weather.condition == "dust" and edge_light:
            add("dust-light", "opportunity", "rule", 0.7, "openShootingWindow", geo_scope="regional")
        if scene is SceneType.VILLAGE and edge_light and clear_enough:
            add("humanity-light", "opportunity", "rule", 0.65, "openExplore", geo_scope="regional")
        if scene is SceneType.DRIVING:
            add("route-light-window", "opportunity", "rule", 0.7, "openRoute", geo_scope="route")
        if scene is SceneType.HIKING:
            add("hiking-return-check", "safety", "rule", 0.8, "openRoute", "caution", "route")

    creative = [event.id for event in events if event.channel in ("opportunity", "wildlifeOpportunity")]
    safety = [event.id for event in events if event.channel in ("safety", "wildlifeSafety")]
    layout = "safety" if safety else "opportunity" if creative else "quiet"
    manifest = Manifest.model_validate({
        "layoutMode": layout,
        "primaryEventId": creative[0] if creative else None,
        "secondaryEventIds": creative[1:3],
        "safetyEventIds": safety,
    })
    opportunities = _opportunities(request, scene, solar, astronomy_events or [], generated_at, target) \
        if request.contract_version == 3 else []
    allowed_actions = list(dict.fromkeys(
        [event.allowed_action for event in events] +
        [action for opportunity in opportunities
         for action in (opportunity.primary_action, opportunity.fallback_action) if action is not None]
    ))
    response = {
        "contextId": f"ctx_{fingerprint}",
        "generatedAt": generated_at,
        "expiresAt": expires_at,
        "scene": scene,
        "fingerprint": fingerprint,
        "stale": request.weather.stale,
        "dataFreshness": {
            "context": "stale" if request.weather.stale else "fresh",
            "weather": "stale" if request.weather.stale else "fresh",
            "weatherObservedAt": request.weather.observed_at,
        },
        "weather": {
            "condition": request.weather.condition,
            "temperatureCelsius": request.weather.temperature_celsius,
            "windSpeedMps": request.weather.wind_speed_mps,
            "windDirectionDegrees": request.weather.wind_direction_degrees,
            "precipitationMm": request.weather.precipitation_mm,
            "visibilityKm": request.weather.visibility_km,
            "cloudCoverPercent": request.weather.cloud_cover_percent,
            "thunder": request.weather.thunder,
            "airQualityIndex": request.weather.air_quality_index,
            "airQualityCategory": request.weather.air_quality_category,
            "primaryPollutant": request.weather.primary_pollutant,
            "airQualityObservedAt": request.weather.air_quality_observed_at,
            "airQualityStale": request.weather.air_quality_stale,
        },
        "sunMoon": {
            "dayPhase": solar.day_phase,
            "sunElevationDegrees": solar.elevation_degrees,
            "sunAzimuthDegrees": solar.azimuth_degrees,
            "moonPhase": moon_phase,
            "moonIllumination": moon_illumination,
        },
        "route": {
            "mode": request.route.mode,
            "stage": request.route.stage,
            "active": request.route.stage == "active",
        },
        "events": events,
        "allowedActions": allowed_actions,
        "manifest": manifest,
    }
    if request.contract_version == 3:
        response["contractVersion"] = 3
        response["opportunities"] = opportunities
        return SnapshotResponseV3.model_validate(response)
    return SnapshotResponse.model_validate(response)
