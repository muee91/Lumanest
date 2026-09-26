import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
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
}
