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

    expect(repository.calls, 8);
    expect(results.map((item) => item.id), {'shared-fuel', 'shared-supply'});
  });

  test('walking corridors request supplies but never fuel', () async {
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

    expect(repository.categories, everyElement(NearbyPlaceCategory.supply));
    expect(results.map((item) => item.category), [NearbyPlaceCategory.supply]);
  });
}

class _FakeNearbyPlaceRepository implements NearbyPlaceRepository {
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
    return [
      NearbyPlace(
        id: category == NearbyPlaceCategory.fuel
            ? 'shared-fuel'
            : 'shared-supply',
        name: category.label,
        category: category,
        point: center,
        distanceMeters: 300,
      ),
    ];
  }
}
