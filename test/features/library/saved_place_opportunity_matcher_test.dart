import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/saved_place_opportunity_matcher.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 10);

  test('matches a saved WGS-84 place within the reviewed target radius', () {
    final session = _session();
    final match = SavedPlaceOpportunityMatcher.match(
      place: const SavedPlace(
        id: 'saved-place',
        name: '湖岸',
        category: 'waterfront',
        latitude: 30,
        longitude: 120,
      ),
      snapshot: _snapshot([session]),
      now: now,
    );
    expect(match?.sessionId, session.id);
    expect(match?.targetId, 'target-id');
  });

  test('normalizes a reviewed GCJ-02 target before matching', () {
    final gcjTarget = _target(
      coordinate: ChinaCoordinateConverter.wgs84ToGcj02(
        const GeoPoint(latitude: 30, longitude: 120),
      ),
      supportedSessions: const [ShootingSessionKind.waterEvening],
    );
    final match = SavedPlaceOpportunityMatcher.match(
      place: const SavedPlace(
        id: 'saved-place',
        name: '湖岸',
        category: 'waterfront',
        latitude: 30,
        longitude: 120,
      ),
      snapshot: _snapshot([_session(target: gcjTarget)]),
      now: now,
    );
    expect(match?.targetId, 'target-id');
  });

  test('does not match outside radius, stale snapshots or unsupported sessions', () {
    final session = _session(kind: ShootingSessionKind.cityBlueHour);
    final place = const SavedPlace(
      id: 'saved-place',
      name: '湖岸',
      category: 'waterfront',
      latitude: 30.02,
      longitude: 120,
    );
    expect(
      SavedPlaceOpportunityMatcher.match(
        place: place,
        snapshot: _snapshot([session]),
        now: now,
      ),
      isNull,
    );
    expect(
      SavedPlaceOpportunityMatcher.match(
        place: const SavedPlace(
          id: 'saved-place',
          name: '湖岸',
          category: 'waterfront',
          latitude: 30,
          longitude: 120,
        ),
        snapshot: _snapshot([_session()]).asStale(),
        now: now,
      ),
      isNull,
    );
  });
}

ContextSnapshot _snapshot(List<ShootingSession> sessions) => ContextSnapshot(
  id: 'snapshot-id',
  observedAt: DateTime.utc(2026, 9, 27, 9),
  expiresAt: DateTime.utc(2026, 9, 27, 11),
  primaryScene: SceneType.lake,
  dayPhase: DayPhase.sunset,
  weather: WeatherType.clear,
  activeRoute: false,
  shootingSessions: sessions,
);

ShootingSession _session({
  ShootingSessionKind kind = ShootingSessionKind.waterEvening,
  ShootingTarget? target,
}) {
  final start = DateTime.utc(2026, 9, 27, 10);
  final phase = ShootingSessionPhase(
    kind: ShootingPhaseKind.warmLight,
    startsAt: start,
    peaksAt: start.add(const Duration(minutes: 10)),
    endsAt: start.add(const Duration(hours: 1)),
    conditionBand: ShootingConditionBand.good,
    directionDegrees: 258,
  );
  return ShootingSession(
    id: 'session-id',
    kind: kind,
    title: '水岸晚光',
    startsAt: start,
    endsAt: start.add(const Duration(hours: 1)),
    primaryPhase: phase.kind,
    conditionBand: ShootingConditionBand.good,
    confidenceBand: ShootingConfidenceBand.high,
    trend: ShootingTrend.stable,
    phases: [phase],
    factors: const [],
    trendSamples: const [],
    targetCandidates: [target ?? _target()],
    ruleVersion: 'test.1',
    expiresAt: DateTime.utc(2026, 9, 27, 11),
  );
}

ShootingTarget _target({
  GeoPoint coordinate = const GeoPoint(latitude: 30, longitude: 120),
  Iterable<ShootingSessionKind> supportedSessions = const [ShootingSessionKind.waterEvening],
}) => ShootingTarget(
  id: 'target-id',
  name: '湖岸机位',
  coordinate: coordinate,
  supportedSessions: supportedSessions,
  viewBearingDegrees: 258,
  bearingToleranceDegrees: 20,
  accessModes: const [ShootingTravelMode.driving],
  leadTimeMinutes: 10,
  arrivalRadiusMeters: 100,
  shorelineSide: ShootingShorelineSide.east,
  reviewedAt: DateTime.utc(2026, 9, 1),
  reviewReference: Uri.parse('https://example.com/review'),
  sourceAttribution: 'test',
  sourceLicense: 'test',
  sourceUrl: Uri.parse('https://example.com/source'),
);
