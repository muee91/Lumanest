import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/active_saved_place.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 4);
  final target = ShootingTarget(
    id: 'target_0123456789abcdef01234567',
    name: '审核湖岸机位',
    coordinate: const GeoPoint(latitude: 30.251, longitude: 120.151),
    supportedSessions: const [ShootingSessionKind.waterEvening],
    viewBearingDegrees: 282,
    bearingToleranceDegrees: 20,
    accessModes: const [ShootingTravelMode.driving],
    leadTimeMinutes: 10,
    arrivalRadiusMeters: 120,
    shorelineSide: ShootingShorelineSide.east,
    reviewedAt: DateTime.utc(2026, 9, 1),
    reviewReference: Uri.parse('https://review.example/targets/lakeshore'),
    sourceAttribution: '审核目录',
    sourceLicense: 'CC-BY-4.0',
    sourceUrl: Uri.parse('https://source.example/targets/lakeshore'),
  );

  test('reactivates a saved place only inside reviewed target radius', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [target],
    );
    const saved = SavedPlace(
      id: 'saved-lakeshore',
      name: '我的湖岸机位',
      category: 'viewpoint',
      latitude: 30.251,
      longitude: 120.151,
      coordinateSystem: CoordinateSystem.wgs84,
    );

    final matches = ActiveSavedPlaceMatcher.match(
      places: const [saved],
      sessions: [session],
      now: now,
    );

    expect(matches, hasLength(1));
    expect(matches.single.place.id, saved.id);
    expect(matches.single.target.id, target.id);
    expect(matches.single.session.id, session.id);
  });

  test('does not reactivate distant or limited saved-place matches', () {
    final limited = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [target],
      confidenceBand: ShootingConfidenceBand.limited,
    );
    const distant = SavedPlace(
      id: 'saved-distant',
      name: '远处地点',
      category: 'viewpoint',
      latitude: 30.30,
      longitude: 120.30,
      coordinateSystem: CoordinateSystem.wgs84,
    );

    expect(
      ActiveSavedPlaceMatcher.match(
        places: const [distant],
        sessions: [limited],
        now: now,
      ),
      isEmpty,
    );
  });

  test('normalizes a reviewed GCJ-02 target before saved-place matching', () {
    const canonical = GeoPoint(latitude: 30.251, longitude: 120.151);
    final gcjTarget = ShootingTarget(
      id: 'target_gcj_0123456789abcdef012345',
      name: '高德审核机位',
      coordinate: ChinaCoordinateConverter.wgs84ToGcj02(canonical),
      supportedSessions: const [ShootingSessionKind.waterEvening],
      viewBearingDegrees: 282,
      bearingToleranceDegrees: 20,
      accessModes: const [ShootingTravelMode.driving],
      leadTimeMinutes: 10,
      arrivalRadiusMeters: 120,
      shorelineSide: ShootingShorelineSide.east,
      reviewedAt: DateTime.utc(2026, 9, 1),
      reviewReference: Uri.parse('https://review.example/targets/gcj'),
      sourceAttribution: '审核目录',
      sourceLicense: 'CC-BY-4.0',
      sourceUrl: Uri.parse('https://source.example/targets/gcj'),
    );
    final session = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [gcjTarget],
    );
    const saved = SavedPlace(
      id: 'saved-canonical',
      name: 'WGS84 收藏点',
      category: 'viewpoint',
      latitude: 30.251,
      longitude: 120.151,
      coordinateSystem: CoordinateSystem.wgs84,
    );

    final matches = ActiveSavedPlaceMatcher.match(
      places: const [saved],
      sessions: [session],
      now: now,
    );

    expect(matches, hasLength(1));
    expect(matches.single.target.id, gcjTarget.id);
  });

  test(
    'does not reactivate a target that does not support the session kind',
    () {
      final unsupported = ShootingTarget(
        id: 'target_unsupported_0123456789abcdef',
        name: '不支持当前题材的机位',
        coordinate: const GeoPoint(latitude: 30.251, longitude: 120.151),
        supportedSessions: const [ShootingSessionKind.cityBlueHour],
        viewBearingDegrees: 282,
        bearingToleranceDegrees: 20,
        accessModes: const [ShootingTravelMode.driving],
        leadTimeMinutes: 10,
        arrivalRadiusMeters: 120,
        shorelineSide: ShootingShorelineSide.east,
        reviewedAt: DateTime.utc(2026, 9, 1),
        reviewReference: Uri.parse(
          'https://review.example/targets/unsupported',
        ),
        sourceAttribution: '审核目录',
        sourceLicense: 'CC-BY-4.0',
        sourceUrl: Uri.parse('https://source.example/targets/unsupported'),
      );
      final session = ContextFixtures.waterEveningSession(
        observedAt: now,
        targetCandidates: [unsupported],
      );
      const saved = SavedPlace(
        id: 'saved-unsupported',
        name: '收藏点',
        category: 'viewpoint',
        latitude: 30.251,
        longitude: 120.151,
        coordinateSystem: CoordinateSystem.wgs84,
      );

      expect(
        ActiveSavedPlaceMatcher.match(
          places: const [saved],
          sessions: [session],
          now: now,
        ),
        isEmpty,
      );
    },
  );

  test('does not match a saved place with an unknown coordinate datum', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [target],
    );
    const saved = SavedPlace(
      id: 'saved-unknown-datum',
      name: '旧版本地点',
      category: 'viewpoint',
      latitude: 30.251,
      longitude: 120.151,
      coordinateSystem: CoordinateSystem.unknown,
    );

    expect(
      ActiveSavedPlaceMatcher.match(
        places: const [saved],
        sessions: [session],
        now: now,
      ),
      isEmpty,
    );
  });

  test('normalizes a saved GCJ-02 place against a WGS84 target', () {
    const canonical = GeoPoint(latitude: 30.251, longitude: 120.151);
    final gcj = ChinaCoordinateConverter.wgs84ToGcj02(canonical);
    final saved = SavedPlace(
      id: 'saved-gcj02',
      name: '高德收藏点',
      category: 'viewpoint',
      latitude: gcj.latitude,
      longitude: gcj.longitude,
      coordinateSystem: CoordinateSystem.gcj02,
    );
    final session = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [target],
    );

    final matches = ActiveSavedPlaceMatcher.match(
      places: [saved],
      sessions: [session],
      now: now,
    );

    expect(matches, hasLength(1));
    expect(matches.single.distanceMeters, lessThan(1));
  });
}
