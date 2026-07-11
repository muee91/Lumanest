import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

class ContextSnapshotBuilder {
  const ContextSnapshotBuilder();

  ContextSnapshot build({
    required LocationReading location,
    required WeatherObservation weather,
    required SolarState solar,
    required DateTime generatedAt,
  }) {
    return ContextSnapshot(
      id: 'live-${generatedAt.microsecondsSinceEpoch}',
      observedAt: weather.observedAt,
      expiresAt: generatedAt.add(const Duration(minutes: 15)),
      primaryScene: SceneType.unknown,
      dayPhase: solar.dayPhase,
      weather: weather.contextWeatherType,
      activeRoute: false,
      opportunityIds: [if (solar.dayPhase == DayPhase.blueHour) 'blue-hour'],
      safetyEventIds: [if (weather.hasThunder) 'thunderstorm'],
      location: location.point,
      temperatureCelsius: weather.temperatureCelsius,
      windSpeedMetersPerSecond: weather.windSpeedMetersPerSecond,
      windDirectionDegrees: weather.windDirectionDegrees,
      visibilityKilometers: weather.visibilityKilometers,
      precipitationMillimeters: weather.precipitationMillimeters,
      cloudCoverPercent: weather.cloudCoverPercent,
      solarElevationDegrees: solar.elevationDegrees,
      solarAzimuthDegrees: solar.azimuthDegrees,
      sunrise: solar.sunrise,
      sunset: solar.sunset,
    );
  }
}
