import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/application/route_elevation_service.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/elevation_profile.dart';

void main() {
  test(
    'converts sampled GCJ route points and calculates gain and loss',
    () async {
      final repository = _FakeElevationRepository([100, 110, 120, 115, 105]);
      final route = _walkingRoute(
        List.generate(
          5,
          (index) => GeoPoint(
            latitude: 31.23 + index / 100,
            longitude: 121.47 + index / 100,
            coordinateSystem: CoordinateSystem.gcj02,
          ),
        ),
      );

      final enriched = await RouteElevationService(repository).enrich(route);

      expect(repository.points, hasLength(5));
      expect(
        repository.points.every(
          (point) => point.coordinateSystem == CoordinateSystem.wgs84,
        ),
        isTrue,
      );
      expect(enriched.ascentMeters, 10);
      expect(enriched.descentMeters, 5);
      expect(enriched.elevationSource, 'test-dem');
    },
  );

  test(
    'bounds long route profiles to 64 samples including endpoints',
    () async {
      final repository = _FakeElevationRepository(List.filled(64, 100));
      final points = List.generate(
        200,
        (index) => GeoPoint(
          latitude: 30 + index / 1000,
          longitude: 120 + index / 1000,
        ),
      );

      await RouteElevationService(repository).enrich(_walkingRoute(points));

      expect(repository.points, hasLength(64));
      expect(repository.points.first, points.first);
      expect(repository.points.last, points.last);
    },
  );

  test('does not request elevation for driving routes', () async {
    final repository = _FakeElevationRepository(const []);
    final route = DrivingRoute(
      destinationName: '机位',
      distanceMeters: 1000,
      durationSeconds: 300,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.1, longitude: 120.1),
      ],
    );

    expect(await RouteElevationService(repository).enrich(route), same(route));
    expect(repository.points, isEmpty);
  });
}

DrivingRoute _walkingRoute(List<GeoPoint> points) => DrivingRoute(
  destinationName: '徒步机位',
  distanceMeters: 3000,
  durationSeconds: 1800,
  tollsYuan: 0,
  polyline: points,
  travelMode: RouteTravelMode.walking,
);

class _FakeElevationRepository implements ElevationProfileRepository {
  _FakeElevationRepository(this.values);
  final List<double> values;
  List<GeoPoint> points = const [];

  @override
  Future<ElevationProfile> fetch(List<GeoPoint> points) async {
    this.points = points;
    return ElevationProfile(source: 'test-dem', elevations: values);
  }
}
