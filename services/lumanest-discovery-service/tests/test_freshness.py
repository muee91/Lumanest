from datetime import datetime, timedelta, timezone

from app.store import FRESHNESS_POLICY, freshness_until


NOW = datetime(2026, 7, 19, 8, 0, tzinfo=timezone.utc)


def test_mission_policies_have_explicit_validity_and_refresh_intervals():
    assert FRESHNESS_POLICY["routeConditions"].valid_seconds == 15 * 60
    assert FRESHNESS_POLICY["routeConditions"].refresh_seconds == 5 * 60
    assert FRESHNESS_POLICY["localStories"].valid_seconds == 30 * 24 * 60 * 60
    assert FRESHNESS_POLICY["humanityEvents"].refresh_seconds == 2 * 60 * 60


def test_humanity_event_expires_at_event_end_when_source_provides_one():
    ends_at = NOW + timedelta(days=2)

    assert freshness_until("humanityEvents", ends_at, now=NOW) == ends_at


def test_humanity_event_without_end_time_gets_a_twelve_hour_expiry():
    assert freshness_until("humanityEvents", None, now=NOW) == NOW + timedelta(hours=12)


def test_non_event_missions_use_their_policy_validity():
    assert freshness_until("popularPlaces", None, now=NOW) == NOW + timedelta(days=1)
    assert freshness_until("hiddenPlaces", None, now=NOW) == NOW + timedelta(days=3)
