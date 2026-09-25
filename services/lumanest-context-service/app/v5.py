from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone
from typing import Any

from .models import SnapshotResponse, V5SnapshotResponse


def project_snapshot_v5(snapshot: SnapshotResponse) -> V5SnapshotResponse:
    generated_at = snapshot.generated_at.astimezone(timezone.utc)
    snapshot_revision = max(1, int(generated_at.timestamp() * 1_000_000))
    source_revisions = {
        "weather": _revision(snapshot.data_freshness.weather_observed_at),
        "solar": _revision(generated_at),
        "astronomy": _revision(generated_at),
        "scene": _revision(generated_at),
        "route": _revision(generated_at),
    }
    sessions_by_definition = {
        definition: session
        for session in snapshot.shooting_sessions
        if (definition := _session_definition(session.kind)) is not None
    }
    normalized_events = _normalized_events(snapshot, sessions_by_definition)
    entries = _entries(snapshot, normalized_events)
    allowed_actions = list(
        dict.fromkeys(
            action["type"] for entry in entries for action in entry["actions"]
        )
    )
    environment = {
        "scene": snapshot.scene,
        "dataFreshness": snapshot.data_freshness.model_dump(mode="json", by_alias=True),
        "weather": snapshot.weather.model_dump(mode="json", by_alias=True),
        "sunMoon": snapshot.sun_moon.model_dump(mode="json", by_alias=True),
        "astronomy": snapshot.astronomy.model_dump(mode="json", by_alias=True),
        "route": snapshot.route.model_dump(mode="json", by_alias=True),
        "sceneContext": snapshot.scene_context.model_dump(mode="json", by_alias=True),
        "allowedActions": allowed_actions,
    }
    facts = {
        "events": normalized_events,
        "shootingSessions": [
            session.model_dump(mode="json", by_alias=True)
            for session in snapshot.shooting_sessions
        ],
    }
    return V5SnapshotResponse.model_validate(
        {
            "contractVersion": 5,
            "contextId": snapshot.context_id,
            "snapshotRevision": snapshot_revision,
            "generatedAt": snapshot.generated_at,
            "expiresAt": snapshot.expires_at,
            "sourceRevisions": source_revisions,
            "stale": snapshot.stale,
            "environment": environment,
            "facts": facts,
            "entries": entries,
            "refreshHints": {
                "weather": "ttl:600",
                "airQuality": "ttl:2700",
                "solar": "phase-boundary",
                "astronomy": "ttl:3600",
                "opportunities": "solar-or-weather-delta",
            },
        }
    )


BASE_SURFACES: tuple[str, ...] = ("today", "explore", "route", "shootingWindow")
INTERRUPT_LEAD_LIMIT = timedelta(hours=2)


def _allowed_surfaces(
    *,
    safety: bool,
    interruptible: bool,
    valid_from: datetime,
    generated_at: datetime,
) -> list[str]:
    """Decide which surfaces may appear without the user asking.

    Safety warnings own the interrupt path at any lead time. A photography entry
    may interrupt only inside the window where its evidence is actually accurate;
    day-scale candidates never reach a notification. This ceiling lives here
    rather than in the client so a view model cannot widen it.
    See docs/core-1.0-scope.md §7.1.
    """
    surfaces = list(BASE_SURFACES)
    if safety:
        return [*surfaces, "widget", "notification"]
    if interruptible:
        surfaces.append("widget")
        if valid_from - generated_at <= INTERRUPT_LEAD_LIMIT:
            surfaces.append("notification")
    return surfaces


def _entries(
    snapshot: SnapshotResponse,
    events: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for event in events:
        event_id = str(event["id"])
        expires_at = datetime.fromisoformat(
            str(event["expiresAt"]).replace("Z", "+00:00")
        )
        observed_at = datetime.fromisoformat(
            str(event["observedAt"]).replace("Z", "+00:00")
        )
        if event_id in seen or expires_at <= snapshot.generated_at:
            continue
        seen.add(event_id)
        safety = event["channel"] in {"safety", "wildlifeSafety"}
        kind = "safety" if safety else "photographyOpportunity"
        variant = "safety" if safety else "manifestOpportunity"
        priority = "p0" if safety else "p2"
        title = event.get("title") or ("安全提醒" if safety else event_id)
        result.append(
            _entry(
                source_id=event_id,
                kind=kind,
                priority=priority,
                severity=str(event["severity"]),
                observed_at=observed_at,
                valid_from=observed_at,
                expires_at=expires_at,
                confidence=float(event["confidence"]),
                action=str(event["allowedAction"]),
                presentation={
                    "variant": variant,
                    "title": title,
                    "shortLabel": title,
                    "fallbackSummary": "查看依据与行动建议" if safety else None,
                },
                payload={
                    "type": "safety" if safety else "opportunity",
                    "eventId": event_id if safety else None,
                    "definitionId": event_id if not safety else None,
                    "instanceId": event_id if not safety else None,
                },
                allowed_surfaces=_allowed_surfaces(
                    safety=safety,
                    interruptible=False,
                    valid_from=observed_at,
                    generated_at=snapshot.generated_at,
                ),
                source_url=event.get("sourceUrl"),
            )
        )
    for session in snapshot.shooting_sessions:
        if session.id in seen or session.expires_at <= snapshot.generated_at:
            continue
        seen.add(session.id)
        result.append(
            _entry(
                source_id=session.id,
                kind="photographyOpportunity",
                priority="p1",
                severity="info",
                observed_at=snapshot.generated_at,
                valid_from=session.start_at,
                expires_at=session.expires_at,
                confidence={"high": 0.9, "medium": 0.7, "limited": 0.4}[
                    session.confidence_band
                ],
                action="openShootingWindow",
                presentation={
                    "variant": "shootingSession",
                    "title": session.title,
                    "shortLabel": session.title,
                    "fallbackSummary": session.title,
                },
                payload={
                    "type": "opportunity",
                    "definitionId": session.id,
                    "instanceId": session.id,
                    "sessionId": session.id,
                },
                allowed_surfaces=_allowed_surfaces(
                    safety=False,
                    # A `limited` band session states conditions it cannot back
                    # up, so it may never be the reason the app speaks first.
                    interruptible=session.confidence_band in {"high", "medium"},
                    valid_from=session.start_at,
                    generated_at=snapshot.generated_at,
                ),
            )
        )
    return result


def _normalized_events(
    snapshot: SnapshotResponse,
    sessions_by_definition: dict[str, Any],
) -> list[dict[str, Any]]:
    """Keep the public V5 action graph referentially valid.

    A shooting-window action is legal only when it targets a concrete
    ShootingSession instance. Session definitions are represented by the
    session entry below, so their legacy event row is omitted. Definitions
    without an implemented session degrade to Explore instead of opening an
    empty detail route.
    """
    result: list[dict[str, Any]] = []
    for event in snapshot.events:
        body = event.model_dump(mode="json", by_alias=True)
        if event.allowed_action != "openShootingWindow":
            result.append(body)
            continue
        if event.id in sessions_by_definition:
            continue
        body["allowedAction"] = "openExplore"
        result.append(body)
    return result


def _session_definition(kind: str) -> str | None:
    return {
        "generalMorning": "session.general.morning",
        "generalEvening": "session.general.evening",
        "waterMorning": "session.water.morning",
        "waterEvening": "session.water.evening",
        "mountainMorning": "session.mountain.morning",
        "mountainEvening": "session.mountain.evening",
        "cityBlueHour": "session.city.blue_hour",
        "cityAfterRain": "session.city.after_rain",
        "desertSideLight": "session.desert.side_light",
        "routeLightWindow": "session.route.light_window",
    }.get(kind)


def _entry(
    *,
    source_id: str,
    kind: str,
    priority: str,
    severity: str,
    observed_at: datetime,
    valid_from: datetime,
    expires_at: datetime,
    confidence: float,
    action: str,
    presentation: dict[str, Any],
    payload: dict[str, Any],
    allowed_surfaces: list[str],
    source_url: str | None = None,
) -> dict[str, Any]:
    entry_id = "entry_" + hashlib.sha256(source_id.encode()).hexdigest()[:24]
    fingerprint_input = json.dumps(
        {"id": entry_id, "presentation": presentation, "payload": payload},
        sort_keys=True,
        ensure_ascii=False,
    ).encode()
    fingerprint = "sha256:" + hashlib.sha256(fingerprint_input).hexdigest()
    return {
        "id": entry_id,
        "kind": kind,
        "sourceNamespace": "contextService.v5",
        "sourceId": source_id,
        "revision": max(1, _revision(observed_at)),
        "observedAt": observed_at,
        "validFrom": valid_from,
        "expiresAt": expires_at,
        "freshness": "fresh",
        "evidenceConfidence": max(0, min(1, confidence)),
        "basePriority": priority,
        "severity": severity,
        "geoScope": "region",
        "allowedSurfaces": allowed_surfaces,
        "actions": [{"type": action, "targetId": source_id}],
        "presentation": presentation,
        "payload": payload,
        "provenance": [
            {
                "sourceId": "context-service",
                "observedAt": observed_at,
                "sourceUrl": source_url,
            }
        ],
        "dedupeKey": source_id,
        "suppressionKeys": [],
        "contentFingerprint": fingerprint,
    }


def _revision(value: datetime) -> int:
    return max(1, int(value.astimezone(timezone.utc).timestamp() * 1_000_000))
