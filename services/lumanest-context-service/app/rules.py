from __future__ import annotations

import hashlib
import math
from datetime import datetime, timedelta, timezone

from .models import (
    ActivityState,
    AstronomyState,
    CompositeSceneContext,
    ContextEvent,
    Manifest,
    PhotographyTarget,
    PrimaryScene,
    SceneEvidence,
    SceneFacet,
    SceneType,
    ShootingTarget,
    SnapshotRequest,
    SnapshotResponse,
)
from .astronomy import astronomy_state
from .shooting_sessions import (
    build_city_after_rain_session,
    build_general_evening_session,
    build_general_morning_session,
    build_route_light_session,
    build_water_evening_session,
    build_water_morning_session,
)
from .generated.opportunity_catalog import OPPORTUNITY_CATALOG, TIMING_POLICIES
from .solar import solar_state


_moon_reference = datetime(2000, 1, 6, 18, 14, tzinfo=timezone.utc)
_synodic_month_days = 29.53058867
_catalog_by_id = {item["id"]: item for item in OPPORTUNITY_CATALOG}
_timing_by_id = {item["id"]: item for item in TIMING_POLICIES}


def _evidence_expiry(definition_id: str, generated_at: datetime) -> datetime:
    definition = _catalog_by_id.get(definition_id)
    timing = _timing_by_id.get(definition.get("timingPolicy")) if definition else None
    raw_ttl = timing.get("evidenceTtl") if timing else None
    if isinstance(raw_ttl, str) and raw_ttl.endswith("m") and raw_ttl[:-1].isdigit():
        return generated_at + timedelta(minutes=int(raw_ttl[:-1]))
    return generated_at + timedelta(minutes=10)


def moon_state(moment: datetime) -> tuple[str, float]:
    age = (
        (moment.astimezone(timezone.utc) - _moon_reference).total_seconds() / 86_400
    ) % _synodic_month_days
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


def classify_scene(
    request: SnapshotRequest, evidence: SceneEvidence | None = None
) -> SceneType:
    facts = evidence or request.evidence
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


def classify_scene_context(
    request: SnapshotRequest, evidence: SceneEvidence | None = None
) -> CompositeSceneContext:
    facts = evidence or request.evidence
    facets = set(facts.scene_facets)
    activity = ActivityState.STATIONARY
    if request.route.stage == "active" and request.route.mode == "driving":
        activity = ActivityState.DRIVING
    elif request.route.stage == "active" and request.route.mode == "hiking":
        activity = ActivityState.HIKING

    if facts.reviewed_primary_scene not in (None, PrimaryScene.UNKNOWN):
        reviewed = facts.reviewed_primary_scene
        return CompositeSceneContext(
            primaryScene=reviewed,
            facets=sorted(facets, key=lambda item: item.value),
            activity=activity,
            scores={reviewed: 100},
            reviewedOverride=True,
        )

    scores: dict[PrimaryScene, int] = {}

    def score(scene: PrimaryScene, value: int) -> None:
        scores[scene] = max(scores.get(scene, 0), value)

    if facts.mountainous or facets.intersection(
        {SceneFacet.REVIEWED_PEAK, SceneFacet.GLACIER, SceneFacet.CANYON}
    ):
        score(PrimaryScene.MOUNTAIN, 60)
    if facts.coast or facets.intersection({SceneFacet.COAST, SceneFacet.TIDAL_FLAT}):
        score(PrimaryScene.COAST, 60)
    if facts.wetland or SceneFacet.WETLAND in facets:
        score(PrimaryScene.WETLAND, 60)
    if facts.arid_land or SceneFacet.DUNE in facets:
        score(PrimaryScene.DESERT, 60)
    if facts.plateau or SceneFacet.GRASSLAND in facets:
        score(PrimaryScene.PLATEAU, 55)
    if facts.forest or facets.intersection(
        {SceneFacet.FOREST, SceneFacet.BAMBOO_FOREST}
    ):
        score(PrimaryScene.FOREST, 55)
    if facts.water_body or facets.intersection({SceneFacet.LAKE, SceneFacet.RESERVOIR}):
        score(PrimaryScene.INLAND_WATER, 55)
    if facts.settlement or facets.intersection(
        {SceneFacet.OLD_TOWN, SceneFacet.VILLAGE_STREET}
    ):
        score(PrimaryScene.VILLAGE, 50)
    if facts.urban or facets.intersection(
        {SceneFacet.SKYLINE, SceneFacet.ARCHITECTURE}
    ):
        score(PrimaryScene.URBAN, 45)
    if SceneFacet.RIVER in facets:
        score(PrimaryScene.INLAND_WATER, 35)

    tie_order = (
        PrimaryScene.MOUNTAIN,
        PrimaryScene.COAST,
        PrimaryScene.WETLAND,
        PrimaryScene.INLAND_WATER,
        PrimaryScene.PLATEAU,
        PrimaryScene.DESERT,
        PrimaryScene.FOREST,
        PrimaryScene.VILLAGE,
        PrimaryScene.URBAN,
        PrimaryScene.UNKNOWN,
    )
    maximum = max(scores.values(), default=0)
    primary = (
        next(
            (scene for scene in tie_order if scores.get(scene, 0) == maximum),
            PrimaryScene.UNKNOWN,
        )
        if scores
        else PrimaryScene.UNKNOWN
    )
    return CompositeSceneContext(
        primaryScene=primary,
        facets=sorted(facets, key=lambda item: item.value),
        activity=activity,
        scores=scores,
        reviewedOverride=False,
    )


def context_fingerprint(
    request: SnapshotRequest,
    scene: SceneType,
    evidence: SceneEvidence | None = None,
    astronomy_events: list[dict] | None = None,
    target: PhotographyTarget | None = None,
    shooting_targets: list[ShootingTarget] | None = None,
    astronomy: AstronomyState | None = None,
) -> str:
    facts = evidence or request.evidence
    solar = request.solar or solar_state(request.coordinate, request.observed_at)
    astronomy_value = astronomy or astronomy_state(
        request.coordinate, request.observed_at
    )
    warning_state = ",".join(
        sorted(
            ":".join(
                (
                    warning.id,
                    warning.observed_at.astimezone(timezone.utc).isoformat(
                        timespec="minutes"
                    ),
                    warning.expires_at.astimezone(timezone.utc).isoformat(
                        timespec="minutes"
                    ),
                    warning.severity,
                    warning.title,
                )
            )
            for warning in request.official_warnings
        )
    )
    weather_state = ":".join(
        (
            request.weather.observed_at.astimezone(timezone.utc).isoformat(
                timespec="minutes"
            ),
            request.weather.condition,
            str(request.weather.temperature_celsius),
            str(round(request.weather.wind_speed_mps, 1)),
            str(request.weather.wind_direction_degrees),
            str(round(request.weather.precipitation_mm, 1)),
            str(round(request.weather.visibility_km, 1)),
            str(request.weather.cloud_cover_percent),
            str(request.weather.thunder),
            str(request.weather.stale),
        )
    )
    forecast_state = ":".join(
        (
            request.forecast.observed_at.astimezone(timezone.utc).isoformat(
                timespec="minutes"
            ),
            str(round(request.forecast.next_hour_precipitation_mm, 1)),
            str(round(request.forecast.next_three_hours_max_wind_speed_mps or 0, 1)),
            str(request.forecast.thunder_next_three_hours),
        )
    )
    # Current opportunities are derived from individual hourly records, rather
    # than the aggregate forecast above.  Keep their bounded, non-identifying
    # state in the fingerprint so a Redis hit cannot return a window generated
    # from an earlier hourly forecast.
    hourly_state = ",".join(
        sorted(
            ":".join(
                (
                    item.at.astimezone(timezone.utc).isoformat(timespec="minutes"),
                    item.condition,
                    str(round(item.cloud_cover_percent, 1))
                    if item.cloud_cover_percent is not None
                    else "unknown",
                    str(round(item.wind_speed_mps, 1)),
                    str(round(item.precipitation_mm, 1)),
                    str(round(item.visibility_km, 1))
                    if item.visibility_km is not None
                    else "unknown",
                    str(item.thunder),
                )
            )
            for item in request.forecast.hourly
        )
    )
    air_state = ":".join(
        (
            str(request.weather.air_quality_index),
            str(request.weather.air_quality_category),
            str(request.weather.primary_pollutant),
            request.weather.air_quality_observed_at.astimezone(timezone.utc).isoformat(
                timespec="minutes"
            )
            if request.weather.air_quality_observed_at is not None
            else "None",
            str(request.weather.air_quality_stale),
        )
    )
    solar_state_value = ":".join(
        (
            solar.day_phase,
            str(solar.elevation_degrees),
            str(solar.azimuth_degrees),
        )
    )
    corridor_state = ",".join(
        ":".join(
            (
                request.route.route_id or "",
                f"{sample.latitude:.4f}",
                f"{sample.longitude:.4f}",
                sample.expected_at.astimezone(timezone.utc).isoformat(
                    timespec="minutes"
                ),
                f"{sample.progress:.4f}",
            )
        )
        for sample in request.route.corridor_samples
    )
    grid = f"{request.coordinate.latitude:.2f},{request.coordinate.longitude:.2f}"
    raw = "|".join(
        (
            str(request.contract_version),
            grid,
            scene.value,
            solar_state_value,
            astronomy_value.model_dump_json(by_alias=True),
            weather_state,
            forecast_state,
            hourly_state,
            air_state,
            warning_state,
            request.route.mode,
            request.route.stage,
            request.intent,
            str(facts.wildlife_opportunity),
            str(facts.wildlife_safety),
            ",".join(
                sorted(
                    str(event.get("external_id", ""))
                    for event in (astronomy_events or [])
                )
            ),
            target.id if target is not None else "",
            ",".join(sorted(item.id for item in (shooting_targets or []))),
            corridor_state,
        )
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def evaluate(
    request: SnapshotRequest,
    evidence: SceneEvidence | None = None,
    astronomy_events: list[dict] | None = None,
    target: PhotographyTarget | None = None,
    shooting_targets: list[ShootingTarget] | None = None,
    astronomy: AstronomyState | None = None,
) -> SnapshotResponse:
    generated_at = request.observed_at.astimezone(timezone.utc)
    expires_at = generated_at + timedelta(minutes=10)
    scene = classify_scene(request, evidence)
    scene_context = classify_scene_context(request, evidence)
    facts = evidence or request.evidence
    astronomy_value = astronomy or astronomy_state(request.coordinate, generated_at)
    fingerprint = context_fingerprint(
        request,
        scene,
        facts,
        astronomy_events,
        target,
        shooting_targets,
        astronomy_value,
    )
    if astronomy_value.status == "geometryOnly":
        moon_phase = astronomy_value.moon_phase
        moon_illumination = astronomy_value.moon_illumination
    else:
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
        geo_scope: str = "region",
        observed_at: datetime | None = None,
        event_expires_at: datetime | None = None,
        title: str | None = None,
        source_url: str | None = None,
    ) -> None:
        events.append(
            ContextEvent.model_validate(
                {
                    "id": event_id,
                    "channel": channel,
                    "source": source,
                    "observedAt": observed_at or request.weather.observed_at,
                    "expiresAt": event_expires_at
                    or _evidence_expiry(event_id, generated_at),
                    "confidence": confidence,
                    "geoScope": geo_scope,
                    "severity": severity,
                    "allowedAction": action,
                    "title": title,
                    "sourceUrl": source_url,
                }
            )
        )

    for catalog_event in astronomy_events or []:
        definition_id = (
            "event.astro.meteor_shower"
            if catalog_event.get("event_type") == "meteorShower"
            else "event.astro.special_authority"
        )
        add(
            definition_id,
            "opportunity",
            "astronomyCatalog",
            1,
            "openAstronomyDetail",
            "info",
            "region",
            catalog_event["starts_at"],
            catalog_event["ends_at"],
            str(catalog_event["title"]),
            str(catalog_event["source_url"]),
        )

    if request.weather.thunder:
        add(
            "thunderstorm",
            "safety",
            "weather",
            1,
            "openSafetyDetail",
            "critical",
            "region",
        )
    if request.weather.wind_speed_mps >= 15:
        add(
            "strong-wind",
            "safety",
            "weather",
            0.9,
            "openSafetyDetail",
            "warning",
            "region",
        )
    if request.weather.precipitation_mm >= 10:
        add(
            "heavy-rain",
            "safety",
            "weather",
            0.9,
            "openSafetyDetail",
            "warning",
            "region",
        )
    if facts.wildlife_safety:
        add(
            "wildlife-safety",
            "wildlifeSafety",
            "official",
            1,
            "openSafetyDetail",
            "warning",
            "region",
        )
    if (
        not request.weather.stale
        and not request.weather.air_quality_stale
        and request.weather.air_quality_index is not None
        and request.weather.air_quality_index >= 150
    ):
        severity = (
            "critical"
            if request.weather.air_quality_index >= 300
            else "warning"
            if request.weather.air_quality_index >= 200
            else "caution"
        )
        add(
            "unhealthy-air",
            "safety",
            "weather",
            0.95,
            "openSafetyDetail",
            severity,
            "region",
        )

    for warning in request.official_warnings:
        if warning.expires_at <= generated_at:
            continue
        add(
            f"weather-warning-{warning.id}",
            "safety",
            "official",
            1,
            "openSafetyDetail",
            warning.severity,
            "region",
            warning.observed_at,
            warning.expires_at,
            warning.title,
        )

    if not request.weather.stale:
        if facts.wildlife_opportunity:
            add(
                "regional-wildlife",
                "wildlifeOpportunity",
                "wildlifeHistorical",
                0.5,
                "openWildlifeDetail",
                "info",
                "region",
            )
        if request.forecast.thunder_next_three_hours:
            add(
                "thunderstorm-forecast",
                "safety",
                "weather",
                0.9,
                "openSafetyDetail",
                "warning",
            )
        if (
            request.forecast.next_three_hours_max_wind_speed_mps is not None
            and request.forecast.next_three_hours_max_wind_speed_mps >= 15
        ):
            add(
                "strong-wind-forecast",
                "safety",
                "weather",
                0.8,
                "openSafetyDetail",
                "caution",
            )
        if request.forecast.next_hour_precipitation_mm >= 5:
            add("rain-soon", "safety", "weather", 0.8, "openSafetyDetail", "caution")
        edge_light = solar.day_phase in ("dawn", "sunset")
        clear_enough = request.weather.condition in ("clear", "cloudy")
        if scene is SceneType.CITY and solar.day_phase == "blueHour":
            add(
                "session.city.blue_hour",
                "opportunity",
                "solar",
                0.9,
                "openShootingWindow",
                geo_scope="point",
            )
        if (
            scene is SceneType.LAKE
            and request.weather.wind_speed_mps <= 3
            and request.weather.precipitation_mm == 0
            and solar.day_phase in ("dawn", "sunset", "blueHour")
        ):
            definition_id = (
                "session.water.morning"
                if solar.day_phase == "dawn"
                else "session.water.evening"
            )
            add(
                definition_id,
                "opportunity",
                "rule",
                0.82,
                "openShootingWindow",
                geo_scope="point",
            )
        if (
            scene is SceneType.MOUNTAIN
            and edge_light
            and clear_enough
            and request.weather.visibility_km >= 10
        ):
            definition_id = (
                "session.mountain.morning"
                if solar.day_phase == "dawn"
                else "session.mountain.evening"
            )
            add(
                definition_id,
                "opportunity",
                "rule",
                0.72,
                "openShootingWindow",
                geo_scope="region",
            )
        if (
            scene is SceneType.DESERT
            and request.weather.condition == "dust"
            and edge_light
        ):
            add(
                "session.desert.side_light",
                "opportunity",
                "rule",
                0.7,
                "openShootingWindow",
                geo_scope="region",
            )
        if request.route.mode == "hiking" and request.route.stage == "active":
            add(
                "trail-return-risk",
                "safety",
                "rule",
                0.8,
                "openRoute",
                "caution",
                "route",
            )

    creative = [
        event.id
        for event in events
        if event.channel in ("opportunity", "wildlifeOpportunity")
    ]
    safety = [
        event.id for event in events if event.channel in ("safety", "wildlifeSafety")
    ]
    layout = "safety" if safety else "opportunity" if creative else "quiet"
    manifest = Manifest.model_validate(
        {
            "layoutMode": layout,
            "primaryEventId": creative[0] if creative else None,
            "secondaryEventIds": creative[1:3],
            "safetyEventIds": safety,
        }
    )
    # The public contract intentionally caps shooting sessions at two.  A
    # route-aligned observation is more actionable than the generic solar
    # fallback during an active/planned route, so retain it before filling the
    # remaining slot with the earliest general session.
    shooting_sessions = sorted(
        filter(
            None,
            (
                build_route_light_session(request, scene),
                build_city_after_rain_session(request, scene),
                build_water_morning_session(request, scene, shooting_targets)
                if scene is SceneType.LAKE
                else build_general_morning_session(request, scene),
                build_water_evening_session(request, scene, shooting_targets)
                if scene is SceneType.LAKE
                else build_general_evening_session(request, scene),
            ),
        ),
        key=lambda session: (
            0 if session.kind == "routeLightWindow" else 1,
            session.start_at,
            session.id,
        ),
    )[:2]
    allowed_actions = list(dict.fromkeys(event.allowed_action for event in events))
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
        "astronomy": astronomy_value,
        "route": {
            "mode": request.route.mode,
            "stage": request.route.stage,
            "active": request.route.stage == "active",
        },
        "events": events,
        "allowedActions": allowed_actions,
        "manifest": manifest,
    }
    response["contractVersion"] = 5
    response["sceneContext"] = scene_context
    response["opportunityCatalogVersion"] = 1
    response["shootingSessions"] = shooting_sessions
    return SnapshotResponse.model_validate(response)
