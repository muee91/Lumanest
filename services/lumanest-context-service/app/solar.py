from __future__ import annotations

import math
from datetime import datetime, timezone

from .models import Coordinate, SolarInput


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
