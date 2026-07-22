from datetime import datetime, timezone

import pytest
from astronomy import Body, Observer

from app import astronomy
from app.models import AstronomyState, Coordinate


OBSERVED_AT = datetime(2026, 7, 22, tzinfo=timezone.utc)


def test_astronomy_geometry_has_physical_ranges_and_ordered_window():
    state = astronomy.astronomy_state(
        Coordinate(latitude=30.53, longitude=120.68), OBSERVED_AT
    )

    assert state.status == "geometryOnly"
    assert state.astronomical_night is False
    assert -90 <= state.moon_altitude_degrees <= 90
    assert 0 <= state.moon_azimuth_degrees < 360
    assert 0 <= state.moon_illumination <= 1
    assert -90 <= state.galactic_center_altitude_degrees <= 90
    assert 0 <= state.galactic_center_azimuth_degrees < 360
    assert state.moonrise_at is not None
    assert state.moonset_at is not None
    window = state.galactic_center_window
    assert window is not None
    assert window.start_at <= window.peak_at <= window.end_at
    assert window.peak_altitude_degrees >= 10


def test_galactic_window_is_only_dark_night_with_core_above_ten_degrees():
    coordinate = Coordinate(latitude=29.65, longitude=91.12)
    observer = Observer(coordinate.latitude, coordinate.longitude)
    state = astronomy.astronomy_state(coordinate, OBSERVED_AT)
    window = state.galactic_center_window
    assert window is not None

    midpoint = window.start_at + (window.end_at - window.start_at) / 2
    time = astronomy._time(midpoint)
    sun = astronomy._horizontal(Body.Sun, observer, time)
    galactic_center = astronomy._horizontal(
        astronomy._GALACTIC_CENTER, observer, time
    )
    assert sun.altitude <= -18
    assert galactic_center.altitude >= 10


def test_polar_day_returns_no_galactic_window_without_breaking_geometry():
    state = astronomy.astronomy_state(
        Coordinate(latitude=89, longitude=0), OBSERVED_AT
    )

    assert state.status == "geometryOnly"
    assert state.astronomical_night is False
    assert state.galactic_center_window is None


def test_astronomy_failure_degrades_to_explicit_unavailable(monkeypatch):
    def fail(*_args, **_kwargs):
        raise RuntimeError("provider failure")

    monkeypatch.setattr(astronomy, "_calculate_astronomy_state", fail)
    state = astronomy.astronomy_state(
        Coordinate(latitude=30.53, longitude=120.68), OBSERVED_AT
    )

    assert state == AstronomyState(status="unavailable")


def test_unavailable_state_rejects_partial_geometry():
    with pytest.raises(ValueError):
        AstronomyState(status="unavailable", moonAltitudeDegrees=20)
