import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

void main() {
  test('combines normalized environment inputs without inventing a scene', () {
    final generatedAt = DateTime.utc(2026, 7, 11, 12);
    final snapshot = const ContextSnapshotBuilder().build(
      location: LocationReading(
        point: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
        recordedAt: generatedAt,
        accuracyMeters: 8,
      ),
      weather: WeatherObservation(
        observedAt: generatedAt,
        temperatureCelsius: 26,
        condition: WeatherCondition.cloudy,
        windSpeedMetersPerSecond: 4,
        windDirectionDegrees: 180,
        visibilityKilometers: 15,
        precipitationMillimeters: 0,
        cloudCoverPercent: 72,
      ),
      solar: SolarState(
        observedAt: generatedAt,
        elevationDegrees: 30,
        azimuthDegrees: 220,
        sunrise: DateTime.utc(2026, 7, 10, 21),
        sunset: DateTime.utc(2026, 7, 11, 11),
        dayPhase: DayPhase.day,
      ),
      generatedAt: generatedAt,
    );

    expect(snapshot.primaryScene, SceneType.unknown);
    expect(snapshot.location?.coordinateSystem, CoordinateSystem.wgs84);
    expect(snapshot.weather, WeatherType.cloudy);
    expect(snapshot.windSpeedMetersPerSecond, 4);
    expect(snapshot.cloudCoverPercent, 72);
    expect(snapshot.solarElevationDegrees, 30);
    expect(snapshot.isStale, isFalse);
  });

  test('thunder observation enters only the safety event channel', () {
    final generatedAt = DateTime.utc(2026, 7, 11, 12);
    final snapshot = const ContextSnapshotBuilder().build(
      location: LocationReading(
        point: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
        recordedAt: generatedAt,
        accuracyMeters: 8,
      ),
      weather: WeatherObservation(
        observedAt: generatedAt,
        temperatureCelsius: 22,
        condition: WeatherCondition.thunder,
        windSpeedMetersPerSecond: 8,
        windDirectionDegrees: 270,
        visibilityKilometers: 4,
        precipitationMillimeters: 10,
      ),
      solar: SolarState(
        observedAt: generatedAt,
        elevationDegrees: 5,
        azimuthDegrees: 250,
        sunrise: null,
        sunset: null,
        dayPhase: DayPhase.sunset,
      ),
      generatedAt: generatedAt,
    );

    expect(snapshot.safetyEventIds, contains('thunderstorm'));
    expect(snapshot.opportunityIds, isNot(contains('thunderstorm')));
  });

  test('stale copy removes weather-dependent creative opportunities', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final live = ContextSnapshot(
      id: 'live',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.lake,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: false,
      opportunityIds: const ['reflection'],
      safetyEventIds: const ['thunderstorm'],
    );

    final stale = live.asStale();

    expect(stale.opportunityIds, isEmpty);
    expect(stale.safetyEventIds, contains('thunderstorm'));
    expect(stale.isStale, isTrue);
  });
}
