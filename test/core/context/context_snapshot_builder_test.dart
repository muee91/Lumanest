import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

LocationReading _location(DateTime generatedAt) => LocationReading(
  point: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
  recordedAt: generatedAt,
  accuracyMeters: 8,
);

WeatherObservation _weather(DateTime generatedAt) => WeatherObservation(
  observedAt: generatedAt,
  temperatureCelsius: 26,
  condition: WeatherCondition.clear,
  windSpeedMetersPerSecond: 2,
  windDirectionDegrees: 180,
  visibilityKilometers: 20,
  precipitationMillimeters: 0,
);

SolarState _solar(DateTime generatedAt) => SolarState(
  observedAt: generatedAt,
  elevationDegrees: 30,
  azimuthDegrees: 220,
  sunrise: DateTime.utc(2026, 7, 10, 21),
  sunset: DateTime.utc(2026, 7, 11, 11),
  dayPhase: DayPhase.day,
);

void main() {
  test('combines normalized environment inputs without inventing a scene', () {
    final generatedAt = DateTime.utc(2026, 7, 11, 12);
    final snapshot = const ContextSnapshotBuilder().build(
      location: _location(generatedAt),
      weather: _weather(generatedAt),
      solar: _solar(generatedAt),
      generatedAt: generatedAt,
    );

    expect(snapshot.primaryScene, SceneType.unknown);
    expect(snapshot.location?.coordinateSystem, CoordinateSystem.wgs84);
    expect(snapshot.weather, WeatherType.clear);
    expect(snapshot.windSpeedMetersPerSecond, 2);
    expect(snapshot.cloudCoverPercent, isNull);
    expect(snapshot.solarElevationDegrees, 30);
    expect(snapshot.isStale, isFalse);
  });

  test('thunder observation enters only the safety event channel', () {
    final generatedAt = DateTime.utc(2026, 7, 11, 12);
    final snapshot = const ContextSnapshotBuilder().build(
      location: _location(generatedAt),
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

  group('route context', () {
    final generatedAt = DateTime.utc(2026, 7, 11, 12);

    ContextSnapshot buildWithRoute(RouteContextState route) =>
        const ContextSnapshotBuilder().build(
          location: _location(generatedAt),
          weather: _weather(generatedAt),
          solar: _solar(generatedAt),
          generatedAt: generatedAt,
          route: route,
        );

    test(
      'planned route does not override the geo scene or set activeRoute',
      () {
        final snapshot = buildWithRoute(
          RouteContextState.planned(ContextRouteMode.driving),
        );

        expect(snapshot.primaryScene, SceneType.unknown);
        expect(snapshot.activeRoute, isFalse);
        expect(snapshot.routeMode, ContextRouteMode.driving);
        expect(snapshot.routeStage, ContextRouteStage.planned);
        expect(snapshot.allowedActions, isEmpty);
        expect(
          snapshot.events.where(
            (event) => event.geoScope == ContextGeoScope.route,
          ),
          isEmpty,
        );
      },
    );

    test('paused route does not override the geo scene or set activeRoute', () {
      final snapshot = buildWithRoute(
        RouteContextState.paused(ContextRouteMode.hiking),
      );

      expect(snapshot.primaryScene, SceneType.unknown);
      expect(snapshot.activeRoute, isFalse);
      expect(snapshot.routeMode, ContextRouteMode.hiking);
      expect(snapshot.routeStage, ContextRouteStage.paused);
      expect(snapshot.allowedActions, isEmpty);
      expect(
        snapshot.events.where(
          (event) => event.geoScope == ContextGeoScope.route,
        ),
        isEmpty,
      );
    });

    test('active driving produces a driving scene and a route event', () {
      final snapshot = buildWithRoute(
        RouteContextState.active(ContextRouteMode.driving),
      );

      expect(snapshot.primaryScene, SceneType.driving);
      expect(snapshot.activeRoute, isTrue);
      expect(snapshot.routeMode, ContextRouteMode.driving);
      expect(snapshot.routeStage, ContextRouteStage.active);
      expect(snapshot.allowedActions, contains(ContextAction.openRoute));
      final routeEvents = snapshot.events
          .where((event) => event.geoScope == ContextGeoScope.route)
          .toList();
      expect(routeEvents, hasLength(1));
      expect(routeEvents.single.id, 'route-light-window');
      expect(routeEvents.single.channel, ContextEventChannel.opportunity);
    });

    test('active hiking produces a hiking scene and a route safety event', () {
      final snapshot = buildWithRoute(
        RouteContextState.active(ContextRouteMode.hiking),
      );

      expect(snapshot.primaryScene, SceneType.hiking);
      expect(snapshot.activeRoute, isTrue);
      expect(snapshot.routeMode, ContextRouteMode.hiking);
      expect(snapshot.routeStage, ContextRouteStage.active);
      expect(snapshot.allowedActions, contains(ContextAction.openRoute));
      final routeEvents = snapshot.events
          .where((event) => event.geoScope == ContextGeoScope.route)
          .toList();
      expect(routeEvents, hasLength(1));
      expect(routeEvents.single.id, 'hiking-return-check');
      expect(routeEvents.single.channel, ContextEventChannel.safety);
    });

    test('none route leaves the snapshot without route fields', () {
      final snapshot = buildWithRoute(RouteContextState.none);

      expect(snapshot.primaryScene, SceneType.unknown);
      expect(snapshot.activeRoute, isFalse);
      expect(snapshot.routeMode, ContextRouteMode.none);
      expect(snapshot.routeStage, ContextRouteStage.none);
      expect(snapshot.allowedActions, isEmpty);
    });
  });
}
