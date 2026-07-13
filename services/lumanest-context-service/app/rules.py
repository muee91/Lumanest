from __future__ import annotations

import hashlib
from datetime import timedelta, timezone

from .models import ContextEvent, Manifest, SceneEvidence, SceneType, SnapshotRequest, SnapshotResponse


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


def context_fingerprint(request: SnapshotRequest, scene: SceneType) -> str:
    grid = f"{request.coordinate.latitude:.2f},{request.coordinate.longitude:.2f}"
    raw = "|".join((
        grid,
        scene.value,
        request.solar.day_phase,
        request.weather.condition,
        request.route.mode,
        request.route.stage,
        request.intent,
    ))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


def evaluate(request: SnapshotRequest, evidence: SceneEvidence | None = None) -> SnapshotResponse:
    generated_at = request.observed_at.astimezone(timezone.utc)
    expires_at = generated_at + timedelta(minutes=15)
    scene = classify_scene(request, evidence)
    fingerprint = context_fingerprint(request, scene)
    events: list[ContextEvent] = []

    def add(
        event_id: str,
        channel: str,
        source: str,
        confidence: float,
        action: str,
        severity: str = "info",
        geo_scope: str = "regional",
    ) -> None:
        events.append(ContextEvent.model_validate({
            "id": event_id,
            "channel": channel,
            "source": source,
            "observedAt": request.weather.observed_at,
            "expiresAt": expires_at,
            "confidence": confidence,
            "geoScope": geo_scope,
            "severity": severity,
            "allowedAction": action,
        }))

    if request.weather.thunder:
        add("thunderstorm", "safety", "weather", 1, "openSafety", "critical", "regional")
    if request.weather.wind_speed_mps >= 15:
        add("strong-wind", "safety", "weather", 0.9, "openSafety", "warning", "regional")
    if request.weather.precipitation_mm >= 10:
        add("heavy-rain", "safety", "weather", 0.9, "openSafety", "warning", "regional")

    if not request.weather.stale:
        edge_light = request.solar.day_phase in ("dawn", "sunset")
        clear_enough = request.weather.condition in ("clear", "cloudy")
        if scene is SceneType.CITY and request.solar.day_phase == "blueHour":
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

    creative = [event.id for event in events if event.channel == "opportunity"]
    safety = [event.id for event in events if event.channel in ("safety", "wildlifeSafety")]
    layout = "safety" if safety else "opportunity" if creative else "quiet"
    manifest = Manifest.model_validate({
        "layoutMode": layout,
        "primaryEventId": creative[0] if creative else None,
        "secondaryEventIds": creative[1:3],
        "safetyEventIds": safety,
    })
    return SnapshotResponse.model_validate({
        "contextId": f"ctx_{fingerprint}",
        "generatedAt": generated_at,
        "expiresAt": expires_at,
        "scene": scene,
        "fingerprint": fingerprint,
        "stale": request.weather.stale,
        "events": events,
        "manifest": manifest,
    })
