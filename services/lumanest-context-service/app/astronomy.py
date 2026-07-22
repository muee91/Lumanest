from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from astronomy import (
    Body,
    DefineStar,
    Direction,
    Equator,
    Horizon,
    Illumination,
    MoonPhase,
    Observer,
    Refraction,
    SearchAltitude,
    SearchRiseSet,
    Time,
)

from .models import AstronomyState, Coordinate, GalacticCenterWindow


logger = logging.getLogger(__name__)

_GALACTIC_CENTER = Body.Star1
_GALACTIC_CENTER_MINIMUM_ALTITUDE = 10.0
_ASTRONOMICAL_NIGHT_SUN_ALTITUDE = -18.0
_SEARCH_LOOKBACK = timedelta(hours=24)
_SEARCH_HORIZON = timedelta(hours=72)

# Sagittarius A* is a stable geometric proxy for the Milky Way core. The
# large distance suppresses parallax; this is deliberately not a visibility
# or photographic-suitability model.
DefineStar(_GALACTIC_CENTER, 17.761133, -29.00781, 26_000)


def astronomy_state(coordinate: Coordinate, moment: datetime) -> AstronomyState:
    """Return bounded geometry without allowing astronomy to break Context."""
    try:
        return _calculate_astronomy_state(coordinate, moment)
    except Exception:
        logger.warning("astronomy_geometry_unavailable", exc_info=True)
        return AstronomyState(status="unavailable")


def _calculate_astronomy_state(
    coordinate: Coordinate, moment: datetime
) -> AstronomyState:
    utc = _require_aware(moment)
    observer = Observer(coordinate.latitude, coordinate.longitude)
    time = _time(utc)
    moon = _horizontal(Body.Moon, observer, time)
    galactic_center = _horizontal(_GALACTIC_CENTER, observer, time)
    sun = _horizontal(Body.Sun, observer, time)
    illumination = Illumination(Body.Moon, time)
    moonrise = SearchRiseSet(Body.Moon, observer, Direction.Rise, time, 2)
    moonset = SearchRiseSet(Body.Moon, observer, Direction.Set, time, 2)
    return AstronomyState(
        status="geometryOnly",
        astronomicalNight=sun.altitude <= _ASTRONOMICAL_NIGHT_SUN_ALTITUDE,
        moonAltitudeDegrees=round(moon.altitude, 4),
        moonAzimuthDegrees=round(moon.azimuth % 360, 4),
        moonriseAt=_datetime(moonrise) if moonrise is not None else None,
        moonsetAt=_datetime(moonset) if moonset is not None else None,
        moonPhase=_phase_name(MoonPhase(time)),
        moonIllumination=round(illumination.phase_fraction, 6),
        galacticCenterAltitudeDegrees=round(galactic_center.altitude, 4),
        galacticCenterAzimuthDegrees=round(galactic_center.azimuth % 360, 4),
        galacticCenterWindow=_next_galactic_center_window(observer, utc),
    )


def _next_galactic_center_window(
    observer: Observer, observed_at: datetime
) -> GalacticCenterWindow | None:
    search_start = observed_at - _SEARCH_LOOKBACK
    search_end = observed_at + _SEARCH_HORIZON
    boundaries = {search_start, search_end, observed_at}
    for body, altitude in (
        (Body.Sun, _ASTRONOMICAL_NIGHT_SUN_ALTITUDE),
        (_GALACTIC_CENTER, _GALACTIC_CENTER_MINIMUM_ALTITUDE),
    ):
        for direction in (Direction.Rise, Direction.Set):
            boundaries.update(
                _altitude_crossings(
                    body, observer, direction, altitude, search_start, search_end
                )
            )

    candidates: list[tuple[datetime, datetime]] = []
    ordered = sorted(boundaries)
    for start, end in zip(ordered, ordered[1:]):
        if end <= observed_at or end <= start:
            continue
        if _qualifies(observer, start + (end - start) / 2):
            candidates.append((start, end))
    if not candidates:
        return None

    # observedAt is a boundary for selecting an active window, but must not
    # split one otherwise continuous geometric interval.
    merged: list[tuple[datetime, datetime]] = []
    for start, end in candidates:
        if merged and start == merged[-1][1]:
            merged[-1] = (merged[-1][0], end)
        else:
            merged.append((start, end))
    start, end = next(
        ((start, end) for start, end in merged if start <= observed_at < end),
        merged[0],
    )
    peak_at, peak_altitude = _peak_altitude(observer, start, end)
    return GalacticCenterWindow(
        startAt=start,
        peakAt=peak_at,
        endAt=end,
        peakAltitudeDegrees=round(peak_altitude, 4),
    )


def _altitude_crossings(
    body: Body,
    observer: Observer,
    direction: Direction,
    altitude: float,
    start: datetime,
    end: datetime,
) -> list[datetime]:
    result: list[datetime] = []
    cursor = start
    while cursor < end:
        crossing = SearchAltitude(
            body,
            observer,
            direction,
            _time(cursor),
            (end - cursor).total_seconds() / 86_400,
            altitude,
        )
        if crossing is None:
            break
        value = _datetime(crossing)
        if value > end:
            break
        result.append(value)
        cursor = value + timedelta(seconds=1)
    return result


def _qualifies(observer: Observer, moment: datetime) -> bool:
    time = _time(moment)
    return (
        _horizontal(Body.Sun, observer, time).altitude
        <= _ASTRONOMICAL_NIGHT_SUN_ALTITUDE
        and _horizontal(_GALACTIC_CENTER, observer, time).altitude
        >= _GALACTIC_CENTER_MINIMUM_ALTITUDE
    )


def _peak_altitude(
    observer: Observer, start: datetime, end: datetime
) -> tuple[datetime, float]:
    candidates = {start, end}
    cursor = start
    while cursor < end:
        candidates.add(cursor)
        cursor += timedelta(minutes=5)
    return max(
        (
            (moment, _horizontal(_GALACTIC_CENTER, observer, _time(moment)).altitude)
            for moment in candidates
        ),
        key=lambda item: item[1],
    )


def _horizontal(body: Body, observer: Observer, time: Time):
    equatorial = Equator(body, time, observer, True, True)
    return Horizon(
        time,
        observer,
        equatorial.ra,
        equatorial.dec,
        Refraction.Airless,
    )


def _phase_name(angle: float) -> str:
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
    return phases[int((angle + 22.5) // 45) % 8]


def _require_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise ValueError("astronomy moment must include a timezone")
    return value.astimezone(timezone.utc)


def _time(value: datetime) -> Time:
    utc = _require_aware(value)
    return Time.Make(
        utc.year,
        utc.month,
        utc.day,
        utc.hour,
        utc.minute,
        utc.second + utc.microsecond / 1_000_000,
    )


def _datetime(value: Time) -> datetime:
    return value.Utc().replace(tzinfo=timezone.utc)
