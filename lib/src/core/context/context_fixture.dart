import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract final class ContextFixtures {
  static final _baseTime = DateTime.utc(2026, 7, 11, 10);

  static ContextSnapshot quietCity() {
    return ContextSnapshot(
      id: 'fixture-city-quiet',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 30)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
    );
  }

  static ContextSnapshot lakeSunset({DateTime? observedAt}) {
    final eventTime = observedAt?.toUtc() ?? _baseTime;
    return ContextSnapshot(
      id: 'fixture-lake-sunset',
      observedAt: eventTime,
      expiresAt: eventTime.add(const Duration(minutes: 20)),
      primaryScene: SceneType.lake,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      activeRoute: false,
      opportunityIds: const ['reflection', 'blue-hour'],
      events: [
        ContextEvent(
          id: 'reflection',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.weather,
          observedAt: eventTime,
          expiresAt: eventTime.add(const Duration(minutes: 20)),
          confidence: 0.78,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openExplore,
        ),
        ContextEvent(
          id: 'blue-hour',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: eventTime,
          expiresAt: eventTime.add(const Duration(minutes: 20)),
          confidence: 0.9,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openShootingWindow,
        ),
      ],
      allowedActions: const [
        ContextAction.openExplore,
        ContextAction.openShootingWindow,
      ],
    );
  }

  static ContextSnapshot mountainDawn() {
    return ContextSnapshot(
      id: 'fixture-mountain-dawn',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 15)),
      primaryScene: SceneType.mountain,
      dayPhase: DayPhase.dawn,
      weather: WeatherType.clear,
      activeRoute: false,
      opportunityIds: const ['alpenglow'],
      events: [
        ContextEvent(
          id: 'alpenglow',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: _baseTime,
          expiresAt: _baseTime.add(const Duration(minutes: 15)),
          confidence: 0.76,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openShootingWindow,
        ),
      ],
      allowedActions: const [ContextAction.openShootingWindow],
    );
  }

  /// Desert dusk fixture — clear, dry conditions with a dust-light
  /// opportunity event.
  static ContextSnapshot desertDusk() {
    final observedAt = DateTime.utc(2026, 7, 11, 18);
    return ContextSnapshot(
      id: 'fixture-desert-dusk',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 25)),
      primaryScene: SceneType.desert,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: false,
      location: const GeoPoint(latitude: 38.9, longitude: 92.3),
      temperatureCelsius: 34.5,
      windSpeedMetersPerSecond: 2.1,
      visibilityKilometers: 30,
      cloudCoverPercent: 5,
      solarElevationDegrees: 8.2,
      opportunityIds: const ['dust-light'],
      events: [
        ContextEvent(
          id: 'dust-light',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.weather,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 25)),
          confidence: 0.72,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openShootingWindow,
        ),
      ],
      allowedActions: const [ContextAction.openShootingWindow],
    );
  }

  /// Village morning fixture — edge light with a humanity-light
  /// opportunity event.
  static ContextSnapshot villageMorning() {
    final observedAt = DateTime.utc(2026, 7, 11, 5, 45);
    return ContextSnapshot(
      id: 'fixture-village-morning',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 20)),
      primaryScene: SceneType.village,
      dayPhase: DayPhase.dawn,
      weather: WeatherType.clear,
      activeRoute: false,
      location: const GeoPoint(latitude: 27.7, longitude: 99.8),
      temperatureCelsius: 12.0,
      windSpeedMetersPerSecond: 1.5,
      visibilityKilometers: 15,
      cloudCoverPercent: 12,
      solarElevationDegrees: -2.5,
      opportunityIds: const ['humanity-light'],
      events: [
        ContextEvent(
          id: 'humanity-light',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 20)),
          confidence: 0.65,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openExplore,
        ),
      ],
      allowedActions: const [ContextAction.openExplore],
    );
  }

  /// Driving active-route fixture — active driving context with a
  /// route-light-window opportunity event.
  static ContextSnapshot drivingActiveRoute() {
    final observedAt = DateTime.utc(2026, 7, 11, 16, 30);
    return ContextSnapshot(
      id: 'fixture-driving-active',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 15)),
      primaryScene: SceneType.driving,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: true,
      location: const GeoPoint(latitude: 30.6, longitude: 104.1),
      temperatureCelsius: 28.3,
      windSpeedMetersPerSecond: 3.0,
      visibilityKilometers: 25,
      cloudCoverPercent: 20,
      solarElevationDegrees: 35.0,
      routeMode: ContextRouteMode.driving,
      routeStage: ContextRouteStage.active,
      opportunityIds: const ['route-light-window'],
      events: [
        ContextEvent(
          id: 'route-light-window',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 15)),
          confidence: 0.58,
          geoScope: ContextGeoScope.route,
          allowedAction: ContextAction.openRoute,
        ),
      ],
      allowedActions: const [ContextAction.openRoute],
    );
  }

  /// Hiking trail fixture — active hiking context with a
  /// hiking-return-check safety event.
  static ContextSnapshot hikingTrail() {
    final observedAt = DateTime.utc(2026, 7, 11, 14, 0);
    return ContextSnapshot(
      id: 'fixture-hiking-trail',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 30)),
      primaryScene: SceneType.hiking,
      dayPhase: DayPhase.day,
      weather: WeatherType.cloudy,
      activeRoute: true,
      location: const GeoPoint(latitude: 31.2, longitude: 103.5),
      temperatureCelsius: 15.6,
      windSpeedMetersPerSecond: 4.2,
      visibilityKilometers: 8,
      cloudCoverPercent: 70,
      solarElevationDegrees: 22.0,
      routeMode: ContextRouteMode.hiking,
      routeStage: ContextRouteStage.active,
      safetyEventIds: const ['hiking-return-check'],
      events: [
        ContextEvent(
          id: 'hiking-return-check',
          channel: ContextEventChannel.safety,
          source: ContextEventSource.rule,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 30)),
          confidence: 0.8,
          geoScope: ContextGeoScope.route,
          safetyLevel: ContextSafetyLevel.caution,
          allowedAction: ContextAction.openSafety,
        ),
      ],
      allowedActions: const [ContextAction.openSafety],
    );
  }
}
