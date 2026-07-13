import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';
import 'package:luma_nest/src/features/route/infrastructure/resilient_driving_route_repository.dart';

void main() {
  final request = DrivingRouteRequest(
    origin: const GeoPoint(latitude: 31, longitude: 121),
    destination: const GeoPoint(latitude: 31.1, longitude: 121.1),
    destinationName: '目的地',
  );
  final route = DrivingRoute(
    destinationName: '目的地',
    distanceMeters: 1000,
    durationSeconds: 300,
    tollsYuan: 0,
    polyline: const [],
  );

  test('writes a successful live route to cache', () async {
    final cache = _FakeRouteCache();
    final repository = ResilientDrivingRouteRepository(
      primary: _FakeRouteRepository(route),
      cache: cache,
    );

    final result = await repository.plan(request);

    expect(result, same(route));
    expect(cache.writtenRoute, same(route));
  });

  test('returns matching stale cache when live planning fails', () async {
    final cached = DrivingRoute(
      destinationName: '目的地',
      distanceMeters: 1200,
      durationSeconds: 400,
      tollsYuan: 0,
      polyline: const [],
      isStale: true,
    );
    final repository = ResilientDrivingRouteRepository(
      primary: _FakeRouteRepository(null),
      cache: _FakeRouteCache(cached: cached),
    );

    expect(await repository.plan(request), same(cached));
  });
}

class _FakeRouteRepository implements DrivingRouteRepository {
  _FakeRouteRepository(this.route);
  final DrivingRoute? route;

  @override
  Future<DrivingRoute> plan(DrivingRouteRequest request) async {
    final value = route;
    if (value == null) {
      throw const DrivingRouteFailure(DrivingRouteFailureKind.network);
    }
    return value;
  }
}

class _FakeRouteCache implements DrivingRouteCache {
  _FakeRouteCache({this.cached});
  final DrivingRoute? cached;
  DrivingRoute? writtenRoute;

  @override
  Future<DrivingRoute?> readMatching(DrivingRouteRequest request) async =>
      cached;

  @override
  Future<void> write(DrivingRouteRequest request, DrivingRoute route) async {
    writtenRoute = route;
  }
}
