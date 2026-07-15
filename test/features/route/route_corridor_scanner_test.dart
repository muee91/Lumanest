import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/route/application/route_corridor_scanner.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

void main() {
  test('samples a bounded corridor and deduplicates repeated POIs', () async {
    final repository = _FakeNearbyPlaceRepository();
    final route = DrivingRoute(
      destinationName: '远方机位',
      distanceMeters: 100000,
      durationSeconds: 7200,
      tollsYuan: 0,
      polyline: List.generate(
        20,
        (index) => GeoPoint(
          latitude: 31 + index / 100,
          longitude: 121 + index / 100,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ),
    );

    final results = await RouteCorridorScanner(repository).scan(route);

    expect(repository.calls, 9);
    expect(results.map((item) => item.place.id), {
      'shared-fuel',
      'shared-food',
      'shared-supply',
    });
    expect(results.every((stop) => stop.routeProgress == 0), isTrue);
  });

  test('walking corridors request food and supplies but never fuel', () async {
    final repository = _FakeNearbyPlaceRepository();
    final route = DrivingRoute(
      destinationName: '徒步机位',
      distanceMeters: 3000,
      durationSeconds: 1800,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(
          latitude: 31,
          longitude: 121,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        GeoPoint(
          latitude: 31.02,
          longitude: 121.02,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ],
      travelMode: RouteTravelMode.walking,
    );

    final results = await RouteCorridorScanner(repository).scan(route);

    expect(repository.categories, isNot(contains(NearbyPlaceCategory.fuel)));
    expect(repository.categories.toSet(), {
      NearbyPlaceCategory.food,
      NearbyPlaceCategory.supply,
    });
    expect(results.map((item) => item.place.category).toSet(), {
      NearbyPlaceCategory.food,
      NearbyPlaceCategory.supply,
    });
  });

  test('keeps successful corridor data when one category fails', () async {
    final repository = _FakeNearbyPlaceRepository(
      failingCategory: NearbyPlaceCategory.food,
    );
    final route = DrivingRoute(
      destinationName: '补给测试',
      distanceMeters: 2000,
      durationSeconds: 1200,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 31, longitude: 121),
        GeoPoint(latitude: 31.01, longitude: 121.01),
      ],
    );

    final results = await RouteCorridorScanner(repository).scan(route);

    expect(results.map((stop) => stop.place.category).toSet(), {
      NearbyPlaceCategory.fuel,
      NearbyPlaceCategory.supply,
    });
  });

  test('fails only when every corridor request fails', () async {
    final repository = _FakeNearbyPlaceRepository(failAll: true);
    final route = DrivingRoute(
      destinationName: '离线路线',
      distanceMeters: 2000,
      durationSeconds: 1200,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 31, longitude: 121),
        GeoPoint(latitude: 31.01, longitude: 121.01),
      ],
    );

    await expectLater(
      RouteCorridorScanner(repository).scan(route),
      throwsA(isA<NearbyPlaceFailure>()),
    );
  });

  test(
    'derives sample progress from geometry rather than point index',
    () async {
      final route = DrivingRoute(
        destinationName: '不均匀折线',
        distanceMeters: 120000,
        durationSeconds: 7200,
        tollsYuan: 0,
        polyline: const [
          GeoPoint(latitude: 0, longitude: 0),
          GeoPoint(latitude: 0.001, longitude: 0),
          GeoPoint(latitude: 1, longitude: 0),
        ],
      );

      final results = await RouteCorridorScanner(
        _ProgressNearbyPlaceRepository(),
      ).scan(route);

      final progress = results.map((stop) => stop.routeProgress).toList();
      expect(progress, hasLength(3));
      expect(progress[1], lessThan(0.01));
      expect(progress.last, 1);
    },
  );
}

class _FakeNearbyPlaceRepository implements NearbyPlaceRepository {
  _FakeNearbyPlaceRepository({this.failingCategory, this.failAll = false});

  final NearbyPlaceCategory? failingCategory;
  final bool failAll;
  int calls = 0;
  final categories = <NearbyPlaceCategory>[];

  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    calls += 1;
    categories.add(category);
    if (failAll || category == failingCategory) {
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.network);
    }
    return [
      NearbyPlace(
        id: 'shared-${category.name}',
        name: category.label,
        category: category,
        point: center,
        distanceMeters: 300,
      ),
    ];
  }
}

class _ProgressNearbyPlaceRepository implements NearbyPlaceRepository {
  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    if (category != NearbyPlaceCategory.fuel) return const [];
    return [
      NearbyPlace(
        id: 'fuel-${center.latitude}',
        name: '加油点',
        category: category,
        point: center,
        distanceMeters: 100,
      ),
    ];
  }
}
