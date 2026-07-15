import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/route/infrastructure/route_support_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 8);
  final route = DrivingRoute(
    destinationName: '山谷',
    distanceMeters: 5000,
    durationSeconds: 1200,
    tollsYuan: 0,
    polyline: const [
      GeoPoint(latitude: 30, longitude: 120),
      GeoPoint(latitude: 30.1, longitude: 120.1),
    ],
  );
  const stops = [
    RouteSupportStop(
      place: NearbyPlace(
        id: 'fuel-1',
        name: '沿途加油站',
        category: NearbyPlaceCategory.fuel,
        point: GeoPoint(
          latitude: 30.05,
          longitude: 120.05,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        distanceMeters: 320,
        address: '山路口',
      ),
      routeProgress: 0.5,
    ),
  ];

  test(
    'round-trips matching route support as explicitly cached data',
    () async {
      final cache = PersistentRouteSupportCache(
        SharedPreferencesAsync(),
        storageKey: 'route-support-roundtrip',
        now: () => now,
      );
      await cache.write(route, stops);

      final restored = await cache.readMatching(route);

      expect(restored?.single.place.name, '沿途加油站');
      expect(
        restored?.single.place.point.coordinateSystem,
        CoordinateSystem.gcj02,
      );
      expect(restored?.single.routeProgress, 0.5);
      expect(restored?.single.cachedAt, now);
    },
  );

  test('rejects a different route and expired support data', () async {
    final preferences = SharedPreferencesAsync();
    const key = 'route-support-matching';
    final cache = PersistentRouteSupportCache(
      preferences,
      storageKey: key,
      now: () => now,
    );
    await cache.write(route, stops);
    final different = DrivingRoute(
      destinationName: '另一处',
      distanceMeters: 5000,
      durationSeconds: 1200,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 31, longitude: 121),
        GeoPoint(latitude: 31.1, longitude: 121.1),
      ],
    );
    expect(await cache.readMatching(different), isNull);

    final expired = PersistentRouteSupportCache(
      preferences,
      storageKey: key,
      now: () => now.add(const Duration(hours: 25)),
    );
    expect(await expired.readMatching(route), isNull);
  });

  test('clear removes cached support coordinates', () async {
    final cache = PersistentRouteSupportCache(
      SharedPreferencesAsync(),
      storageKey: 'route-support-clear',
      now: () => now,
    );
    await cache.write(route, stops);

    await cache.clear();

    expect(await cache.readMatching(route), isNull);
  });
}
