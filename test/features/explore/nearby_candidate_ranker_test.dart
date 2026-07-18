import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/nearby_candidate_ranker.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/popular_place_evidence.dart';

void main() {
  NearbyPlace place({
    required String id,
    required String name,
    required int distance,
    int? drivingSeconds,
    int sources = 0,
    NearbyAdministrativeRelation relation =
        NearbyAdministrativeRelation.sameCity,
    String keyword = '观景台',
  }) => NearbyPlace(
    id: id,
    name: name,
    category: NearbyPlaceCategory.sunriseCandidate,
    point: GeoPoint(
      latitude: 30.5 + distance / 1000000,
      longitude: 120.7,
      coordinateSystem: CoordinateSystem.gcj02,
    ),
    distanceMeters: distance,
    matchedKeyword: keyword,
    administrativeRelation: relation,
    drivingDurationSeconds: drivingSeconds,
    sourceEvidenceCount: sources,
  );

  test('AI evidence boosts but cannot outweigh a much shorter real drive', () {
    final shortDrive = place(
      id: 'short',
      name: '近处候选',
      distance: 10000,
      drivingSeconds: 1200,
    );
    final sourcedLongDrive = place(
      id: 'sourced',
      name: '资料候选',
      distance: 12000,
      drivingSeconds: 6500,
      sources: 4,
    );

    final result = NearbyCandidateRanker.rank([
      sourcedLongDrive,
      shortDrive,
    ], radiusMeters: 50000);

    expect(result.first.id, 'short');
  });

  test('source candidate merges into the matching AMap POI by name', () {
    final result = NearbyCandidateRanker.mergeEvidence(
      [place(id: 'amap', name: '观海园', distance: 23800, keyword: '观海')],
      const [
        PopularPlaceEvidence(
          id: 'source',
          title: '海盐观海园',
          point: GeoPoint(latitude: 30.5048, longitude: 120.9509),
          distanceMeters: 23800,
          sourceCount: 2,
        ),
      ],
      NearbyPlaceCategory.sunriseCandidate,
    );

    expect(result, hasLength(1));
    expect(result.single.sourceEvidenceCount, 2);
    expect(result.single.aiDiscovered, isFalse);
  });

  test('shortlist keeps keyword diversity before filling by distance', () {
    final candidates = [
      for (var index = 0; index < 8; index++)
        place(
          id: 'view-$index',
          name: '观景台$index',
          distance: 1000 + index * 100,
        ),
      place(id: 'windmill', name: '海盐大风车', distance: 28200, keyword: '风车'),
    ];

    final result = NearbyCandidateRanker.shortlist(candidates, maximum: 4);

    expect(result.map((item) => item.id), contains('windmill'));
  });
}
