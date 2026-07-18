from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from .models import Coordinate, SolarInput


@dataclass(frozen=True)
class EveningSolarWindow:
    sunset: datetime
    blue_hour_start: datetime
    blue_hour_end: datetime


@dataclass(frozen=True)
class MorningSolarWindow:
    blue_hour_start: datetime
    blue_hour_end: datetime
    sunrise: datetime


def solar_state(coordinate: Coordinate, moment: datetime) -> SolarInput:
    utc = moment.astimezone(timezone.utc)
    julian_day = utc.timestamp() / 86_400 + 2_440_587.5
    days = julian_day - 2_451_545.0
    mean_longitude = math.radians((280.46 + 0.9856474 * days) % 360)
    mean_anomaly = math.radians((357.528 + 0.9856003 * days) % 360)
    ecliptic_longitude = mean_longitude + math.radians(
        1.915 * math.sin(mean_anomaly) + 0.020 * math.sin(2 * mean_anomaly)
    )
    obliquity = math.radians(23.439 - 0.0000004 * days)
    right_ascension = math.atan2(
        math.cos(obliquity) * math.sin(ecliptic_longitude),
        math.cos(ecliptic_longitude),
    )
    declination = math.asin(math.sin(obliquity) * math.sin(ecliptic_longitude))
    sidereal = math.radians(
        (280.46061837 + 360.98564736629 * (julian_day - 2_451_545.0)
         + coordinate.longitude) % 360
    )
    hour_angle = (sidereal - right_ascension + math.pi) % (2 * math.pi) - math.pi
    latitude = math.radians(coordinate.latitude)
    elevation = math.asin(
        math.sin(latitude) * math.sin(declination)
        + math.cos(latitude) * math.cos(declination) * math.cos(hour_angle)
    )
    azimuth = (
        math.degrees(
            math.atan2(
                math.sin(hour_angle),
                math.cos(hour_angle) * math.sin(latitude)
                - math.tan(declination) * math.cos(latitude),
            )
        )
        + 180
    ) % 360
    elevation_degrees = math.degrees(elevation)
    if elevation_degrees >= 10:
        day_phase = "day"
    elif azimuth < 180 and elevation_degrees >= -12:
        day_phase = "dawn"
    elif azimuth >= 180 and elevation_degrees >= -6:
        day_phase = "sunset"
    elif azimuth >= 180 and elevation_degrees >= -12:
        day_phase = "blueHour"
    else:
        day_phase = "night"
    return SolarInput.model_validate(
        {
            "dayPhase": day_phase,
            "elevationDegrees": round(elevation_degrees, 4),
            "azimuthDegrees": round(azimuth, 4),
        }
    )


def next_evening_window(
    coordinate: Coordinate, observed_at: datetime
) -> EveningSolarWindow | None:
    """Return the current or next photographic evening using solar elevation.

    Sunset is the descending -0.833 degree crossing. LumaNest's published
    photographic blue-hour convention is the descending -4 to -8 degree span.
    The search includes the current evening when the app opens after sunset.
    """
    if observed_at.tzinfo is None:
        raise ValueError("observed_at must include a timezone")
    search_start = observed_at - timedelta(hours=12)
    search_end = observed_at + timedelta(hours=30)
    sunsets = _descending_crossings(coordinate, search_start, search_end, -0.833)
    blue_starts = _descending_crossings(coordinate, search_start, search_end, -4.0)
    blue_ends = _descending_crossings(coordinate, search_start, search_end, -8.0)
    for blue_end in blue_ends:
        if blue_end <= observed_at:
            continue
        blue_start = next(
            (value for value in reversed(blue_starts) if value < blue_end), None
        )
        sunset = next((value for value in reversed(sunsets) if value < blue_end), None)
        if (
            sunset is not None
            and blue_start is not None
            and sunset < blue_start < blue_end
            and blue_end - sunset <= timedelta(hours=3)
        ):
            return EveningSolarWindow(
                sunset=sunset,
                blue_hour_start=blue_start,
                blue_hour_end=blue_end,
            )
    return None


def next_morning_window(
    coordinate: Coordinate, observed_at: datetime
) -> MorningSolarWindow | None:
    """Return the active or next photographic morning from solar crossings.

    Morning blue hour uses the ascending -8 to -4 degree span. Sunrise is the
    ascending -0.833 degree crossing. The current morning remains eligible
    until 45 minutes after sunrise so an active warm-light phase is not
    replaced by tomorrow's forecast.
    """
    if observed_at.tzinfo is None:
        raise ValueError("observed_at must include a timezone")
    search_start = observed_at - timedelta(hours=12)
    search_end = observed_at + timedelta(hours=30)
    blue_starts = _ascending_crossings(coordinate, search_start, search_end, -8.0)
    blue_ends = _ascending_crossings(coordinate, search_start, search_end, -4.0)
    sunrises = _ascending_crossings(coordinate, search_start, search_end, -0.833)
    for sunrise in sunrises:
        if sunrise + timedelta(minutes=45) <= observed_at:
            continue
        blue_end = next(
            (value for value in reversed(blue_ends) if value < sunrise), None
        )
        blue_start = next(
            (value for value in reversed(blue_starts) if value < sunrise), None
        )
        if (
            blue_start is not None
            and blue_end is not None
            and blue_start < blue_end < sunrise
            and sunrise - blue_start <= timedelta(hours=3)
        ):
            return MorningSolarWindow(
                blue_hour_start=blue_start,
                blue_hour_end=blue_end,
                sunrise=sunrise,
            )
    return None


def _descending_crossings(
    coordinate: Coordinate,
    start: datetime,
    end: datetime,
    threshold: float,
) -> list[datetime]:
    step = timedelta(minutes=10)
    result: list[datetime] = []
    left = start
    left_value = _elevation(coordinate, left) - threshold
    while left < end:
        right = min(left + step, end)
        right_value = _elevation(coordinate, right) - threshold
        if left_value >= 0 and right_value < 0:
            result.append(
                _bisect_descending_crossing(
                    coordinate, left, right, threshold
                )
            )
        left, left_value = right, right_value
    return result


def _ascending_crossings(
    coordinate: Coordinate,
    start: datetime,
    end: datetime,
    threshold: float,
) -> list[datetime]:
    step = timedelta(minutes=10)
    result: list[datetime] = []
    left = start
    left_value = _elevation(coordinate, left) - threshold
    while left < end:
        right = min(left + step, end)
        right_value = _elevation(coordinate, right) - threshold
        if left_value < 0 and right_value >= 0:
            result.append(
                _bisect_ascending_crossing(
                    coordinate, left, right, threshold
                )
            )
        left, left_value = right, right_value
    return result


def _bisect_descending_crossing(
    coordinate: Coordinate,
    left: datetime,
    right: datetime,
    threshold: float,
) -> datetime:
    for _ in range(24):
        midpoint = left + (right - left) / 2
        if _elevation(coordinate, midpoint) >= threshold:
            left = midpoint
        else:
            right = midpoint
    return right.replace(microsecond=0)


def _bisect_ascending_crossing(
    coordinate: Coordinate,
    left: datetime,
    right: datetime,
    threshold: float,
) -> datetime:
    for _ in range(24):
        midpoint = left + (right - left) / 2
        if _elevation(coordinate, midpoint) < threshold:
            left = midpoint
        else:
            right = midpoint
    return right.replace(microsecond=0)


def _elevation(coordinate: Coordinate, moment: datetime) -> float:
    return solar_state(coordinate, moment).elevation_degrees or 0.0
