"""Opening-ceiling contract: which surfaces may appear without the user asking.

docs/core-1.0-scope.md §7.1 makes the interrupt permission a function of the
evidence's own time scale. These tests pin that ceiling in one place so neither
a view model nor a later feature can widen it by accident.
"""

from datetime import datetime, timedelta, timezone

from app.models import HourlyForecastInput, OfficialWarningInput
from app.rules import evaluate
from app.v5 import INTERRUPT_LEAD_LIMIT, _allowed_surfaces, project_snapshot_v5
from test_rules import request_for

GENERATED = datetime(2026, 7, 14, 6, 0, tzinfo=timezone.utc)
BASE = ["today", "explore", "route", "shootingWindow"]


def surfaces(*, safety: bool, interruptible: bool, lead: timedelta) -> list[str]:
    return _allowed_surfaces(
        safety=safety,
        interruptible=interruptible,
        valid_from=GENERATED + lead,
        generated_at=GENERATED,
    )


def test_official_safety_warnings_keep_the_interrupt_path():
    # A warning about a window hours away is still worth interrupting for.
    granted = surfaces(safety=True, interruptible=False, lead=timedelta(days=3))

    assert granted == [*BASE, "widget", "notification"]


def test_confirmed_window_inside_the_evidence_horizon_may_interrupt():
    granted = surfaces(safety=False, interruptible=True, lead=INTERRUPT_LEAD_LIMIT)

    assert "notification" in granted
    assert "widget" in granted


def test_day_scale_window_never_reaches_a_notification():
    denied = surfaces(
        safety=False,
        interruptible=True,
        lead=INTERRUPT_LEAD_LIMIT + timedelta(minutes=1),
    )

    assert "notification" not in denied
    assert denied == [*BASE, "widget"]


def test_entry_that_states_less_than_it_implies_stays_quiet():
    denied = surfaces(safety=False, interruptible=False, lead=timedelta(minutes=5))

    assert denied == BASE


def test_projected_warning_entry_can_interrupt_end_to_end():
    warning = OfficialWarningInput.model_validate(
        {
            "id": "a1b2c3d4e5f6",
            "observedAt": "2026-07-14T14:00:00+08:00",
            "expiresAt": "2026-07-14T20:00:00+08:00",
            "severity": "warning",
            "title": "雷雨大风预警",
        }
    )
    request = request_for(evidence={"waterBody": True}).model_copy(
        update={"official_warnings": [warning]}
    )

    projected = project_snapshot_v5(evaluate(request))
    safety_entries = [
        entry for entry in projected.entries if entry.kind == "safety"
    ]

    assert safety_entries, "official warning must produce a safety entry"
    assert all("notification" in entry.allowed_surfaces for entry in safety_entries)


def test_a_window_farther_out_than_its_evidence_horizon_stays_quiet():
    request = request_for(
        evidence={"urban": True},
        route={
            "mode": "driving",
            "stage": "active",
            "routeId": "route_haining_sunset",
            "corridorSamples": [
                {
                    "latitude": 30.25,
                    "longitude": 120.15,
                    "system": "wgs84",
                    "expectedAt": "2026-07-14T18:30:00+08:00",
                    "progress": 0.3,
                },
                {
                    "latitude": 30.28,
                    "longitude": 120.2,
                    "system": "wgs84",
                    "expectedAt": "2026-07-14T19:00:00+08:00",
                    "progress": 0.8,
                },
            ],
        },
    )
    request.forecast.hourly = [
        HourlyForecastInput.model_validate(
            {
                "at": (request.observed_at + timedelta(hours=offset)).isoformat(),
                "condition": "clear",
                "cloudCoverPercent": 35,
                "windSpeedMps": 2,
                "precipitationMm": 0,
                "visibilityKm": 20,
                "thunder": False,
            }
        )
        for offset in range(24)
    ]
    result = evaluate(request)

    projected = project_snapshot_v5(result)
    session_entries = [
        entry
        for entry in projected.entries
        if entry.presentation.variant == "shootingSession"
    ]

    assert session_entries, "route corridor fixture must produce a session entry"
    for entry in session_entries:
        lead = entry.valid_from - result.generated_at
        assert lead > INTERRUPT_LEAD_LIMIT, "fixture must look beyond the horizon"
        assert "notification" not in entry.allowed_surfaces
        assert "widget" in entry.allowed_surfaces
