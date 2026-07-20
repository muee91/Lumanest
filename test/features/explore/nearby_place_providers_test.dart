import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/popular_place_evidence.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';

void main() {
  test(
    'optional discovery evidence failure keeps real POI flow available',
    () async {
      final result = await fetchOptionalPopularPlaceEvidence(
        _FailingEvidenceRepository(),
        center: const GeoPoint(latitude: 30, longitude: 120),
        radiusMeters: 5000,
        focus: '附近观景地点',
      );

      expect(result, isEmpty);
    },
  );

  test('POI failure leaves the discovery lane available', () async {
    final result = await fetchOptionalNearbyPlaces(
      _FailingNearbyPlaceRepository(),
      center: const GeoPoint(latitude: 30, longitude: 120),
      category: NearbyPlaceCategory.viewpoint,
      radiusMeters: 5000,
    );

    expect(result, isEmpty);
  });
}

class _FailingEvidenceRepository implements PopularPlaceEvidenceRepository {
  @override
  Future<List<PopularPlaceEvidence>> fetch({
    required GeoPoint center,
    required int radiusMeters,
    required String focus,
  }) async {
    throw StateError('discovery service unavailable');
  }
}

class _FailingNearbyPlaceRepository implements NearbyPlaceRepository {
  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    throw const NearbyPlaceFailure(NearbyPlaceFailureKind.network);
  }
}
