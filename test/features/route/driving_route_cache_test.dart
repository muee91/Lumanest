import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 10);
  final request = DrivingRouteRequest(
    origin: const GeoPoint(latitude: 31.23, longitude: 121.47),
    destination: const GeoPoint(
      latitude: 31.24,
      longitude: 121.50,
      coordinateSystem: CoordinateSystem.gcj02,
    ),
    destinationName: '测试机位',
  );
  final route = DrivingRoute(
    destinationName: '测试机位',
    distanceMeters: 5000,
    durationSeconds: 900,
    tollsYuan: 0,
    polyline: const [
      GeoPoint(
        latitude: 31.23,
        longitude: 121.48,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
    ],
    instructions: const ['向东行驶'],
  );

  test('round-trips a matching route as an explicitly stale result', () async {
    final cache = PersistentDrivingRouteCache(
      SharedPreferencesAsync(),
      storageKey: 'route-cache-roundtrip',
      now: () => now,
    );
    await cache.write(request, route);

    final restored = await cache.readMatching(request);

    expect(restored?.destinationName, '测试机位');
    expect(restored?.isStale, isTrue);
    expect(restored?.cachedAt, now);
    expect(restored?.polyline.single.coordinateSystem, CoordinateSystem.gcj02);
  });

  test('rejects a different origin, destination or expired route', () async {
    final preferences = SharedPreferencesAsync();
    final cache = PersistentDrivingRouteCache(
      preferences,
      storageKey: 'route-cache-matching',
      now: () => now,
    );
    await cache.write(request, route);

    final movedOrigin = DrivingRouteRequest(
      origin: const GeoPoint(latitude: 32.23, longitude: 121.47),
      destination: request.destination,
      destinationName: request.destinationName,
    );
    expect(await cache.readMatching(movedOrigin), isNull);

    final expired = PersistentDrivingRouteCache(
      preferences,
      storageKey: 'route-cache-matching',
      now: () => now.add(const Duration(hours: 25)),
    );
    expect(await expired.readMatching(request), isNull);

    final walkingRequest = DrivingRouteRequest(
      origin: request.origin,
      destination: request.destination,
      destinationName: request.destinationName,
      travelMode: RouteTravelMode.walking,
    );
    expect(await cache.readMatching(walkingRequest), isNull);
  });

  test('round-trips walking elevation metadata', () async {
    final cache = PersistentDrivingRouteCache(
      SharedPreferencesAsync(),
      storageKey: 'route-cache-elevation',
      now: () => now,
    );
    final walkingRequest = DrivingRouteRequest(
      origin: request.origin,
      destination: request.destination,
      destinationName: request.destinationName,
      travelMode: RouteTravelMode.walking,
    );
    final walkingRoute = DrivingRoute(
      destinationName: request.destinationName,
      distanceMeters: 3000,
      durationSeconds: 1800,
      tollsYuan: 0,
      polyline: route.polyline,
      travelMode: RouteTravelMode.walking,
      ascentMeters: 128,
      descentMeters: 64,
      elevationSource: 'Open-Meteo Elevation API',
    );

    await cache.write(walkingRequest, walkingRoute);
    final restored = await cache.readMatching(walkingRequest);

    expect(restored?.ascentMeters, 128);
    expect(restored?.descentMeters, 64);
    expect(restored?.elevationSource, 'Open-Meteo Elevation API');
  });

  test('clear removes the persisted route including its polyline', () async {
    final cache = PersistentDrivingRouteCache(
      SharedPreferencesAsync(),
      storageKey: 'route-cache-clear',
      now: () => now,
    );
    await cache.write(request, route);

    await cache.clear();

    expect(await cache.readMatching(request), isNull);
  });
}
