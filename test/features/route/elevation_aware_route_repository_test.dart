import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/application/route_elevation_service.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/elevation_profile.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';
import 'package:luma_nest/src/features/route/infrastructure/elevation_aware_route_repository.dart';

void main() {
  final request = DrivingRouteRequest(
    origin: const GeoPoint(latitude: 31, longitude: 121),
    destination: const GeoPoint(latitude: 31.1, longitude: 121.1),
    destinationName: '徒步机位',
    travelMode: RouteTravelMode.walking,
  );
  final route = DrivingRoute(
    destinationName: '徒步机位',
    distanceMeters: 3000,
    durationSeconds: 1800,
    tollsYuan: 0,
    polyline: const [
      GeoPoint(latitude: 31, longitude: 121),
      GeoPoint(latitude: 31.1, longitude: 121.1),
    ],
    travelMode: RouteTravelMode.walking,
  );

  test('enriches and persists a live walking route', () async {
    final cache = _FakeCache();
    final repository = ElevationAwareRouteRepository(
      base: _FakeRouteRepository(route),
      elevation: RouteElevationService(_ElevationRepository()),
      cache: cache,
    );

    final result = await repository.plan(request);

    expect(result.ascentMeters, 20);
    expect(cache.route?.ascentMeters, 20);
  });

  test('elevation failure keeps the base walking route usable', () async {
    final repository = ElevationAwareRouteRepository(
      base: _FakeRouteRepository(route),
      elevation: RouteElevationService(_FailingElevationRepository()),
      cache: _FakeCache(),
    );

    final result = await repository.plan(request);

    expect(result, same(route));
    expect(result.ascentMeters, isNull);
  });
}

class _FakeRouteRepository implements DrivingRouteRepository {
  _FakeRouteRepository(this.route);
  final DrivingRoute route;

  @override
  Future<DrivingRoute> plan(DrivingRouteRequest request) async => route;
}

class _ElevationRepository implements ElevationProfileRepository {
  @override
  Future<ElevationProfile> fetch(List<GeoPoint> points) async =>
      ElevationProfile(source: 'dem', elevations: const [100, 120]);
}

class _FailingElevationRepository implements ElevationProfileRepository {
  @override
  Future<ElevationProfile> fetch(List<GeoPoint> points) async =>
      throw StateError('offline');
}

class _FakeCache implements DrivingRouteCache {
  DrivingRoute? route;

  @override
  Future<DrivingRoute?> readMatching(DrivingRouteRequest request) async => null;

  @override
  Future<void> write(DrivingRouteRequest request, DrivingRoute route) async {
    this.route = route;
  }
}
