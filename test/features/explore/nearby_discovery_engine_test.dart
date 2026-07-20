import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_context.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_engine.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

void main() {
  test('passive discovery is capped at three entries', () {
    final now = DateTime.now().toUtc();
    final context = _context(now, NearbyDiscoveryMode.passive);
    final result = const NearbyDiscoveryEngine().rank(
      List.generate(5, (index) => _place(index)),
      context,
    );

    expect(result.places, hasLength(3));
    expect(result.entries, hasLength(3));
  });

  test('supported POI evidence does not imply a reviewed shooting target', () {
    final now = DateTime.now().toUtc();
    final result = const NearbyDiscoveryEngine().rank([
      _place(0),
    ], _context(now, NearbyDiscoveryMode.explicit));

    expect(result.entries, hasLength(1));
    final payload = result.entries.single.payload as PlaceEntryPayload;
    expect(payload.reviewedTarget, isFalse);
    expect(result.entries.single.presentation.detail, contains('尚未审核为机位'));
  });
}

NearbyDiscoveryContext _context(DateTime now, NearbyDiscoveryMode mode) {
  final point = const GeoPoint(latitude: 30.25, longitude: 120.15);
  return NearbyDiscoveryContext(
    origin: point,
    searchCenter: point,
    radiusMeters: 5000,
    intent: NearbyPlaceCategory.viewpoint,
    mode: mode,
    now: now,
    snapshot: ContextFixtures.lakeSunset(observedAt: now),
  );
}

NearbyPlace _place(int index) {
  return NearbyPlace(
    id: 'place-$index',
    name: '候选地点 $index',
    category: NearbyPlaceCategory.viewpoint,
    point: GeoPoint(latitude: 30.25 + index * .001, longitude: 120.15),
    distanceMeters: 300 + index * 100,
    administrativeRelation: NearbyAdministrativeRelation.sameDistrict,
    drivingDurationSeconds: 600 + index * 60,
    sourceEvidenceCount: 3,
  );
}
