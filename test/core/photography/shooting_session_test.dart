import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

void main() {
  final now = DateTime.utc(2026, 7, 17, 10);
  final target = ShootingTarget(
    id: 'target_0123456789abcdef01234567',
    name: '东岸审核湖岸',
    coordinate: const GeoPoint(latitude: 30.251, longitude: 120.151),
    supportedSessions: const [ShootingSessionKind.waterEvening],
    viewBearingDegrees: 286,
    bearingToleranceDegrees: 25,
    accessModes: const [ShootingTravelMode.driving],
    leadTimeMinutes: 10,
    arrivalRadiusMeters: 100,
    shorelineSide: ShootingShorelineSide.east,
    reviewedAt: DateTime.utc(2026, 7, 1),
    reviewReference: Uri.parse('https://review.example/targets/east-bank'),
    sourceAttribution: '审核目录',
    sourceLicense: 'CC-BY-4.0',
    sourceUrl: Uri.parse('https://source.example/lakes/east-bank'),
  );

  test('withholds departure promises when no reviewed target exists', () {
    final session = ContextFixtures.waterEveningSession(observedAt: now);

    final decision = ShootingExecutionResolver.resolve(
      session: session,
      now: now,
      routeDuration: const Duration(minutes: 5),
    );

    expect(decision.state, ShootingExecutionState.observe);
    expect(decision.departureDeadline, isNull);
  });

  test('uses route duration plus target lead time for latest departure', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [target],
    );

    final decision = ShootingExecutionResolver.resolve(
      session: session,
      now: now,
      target: target,
      routeDuration: const Duration(minutes: 5),
    );

    expect(decision.state, ShootingExecutionState.departNow);
    expect(
      decision.departureDeadline,
      session.phases[1].startsAt.subtract(const Duration(minutes: 15)),
    );
  });

  test('limited confidence stays observational even with a route', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: now,
      targetCandidates: [target],
      confidenceBand: ShootingConfidenceBand.limited,
    );

    final decision = ShootingExecutionResolver.resolve(
      session: session,
      now: now,
      target: target,
      routeDuration: const Duration(minutes: 5),
    );

    expect(decision.state, ShootingExecutionState.observe);
    expect(decision.reason, contains('只适合观察'));
  });

  test('watch mode opens only within the bounded foreground lead time', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: now.add(const Duration(hours: 4)),
    );

    expect(session.canStartWatchingAt(now), isFalse);
    expect(
      session.canStartWatchingAt(
        now.add(const Duration(hours: 1, minutes: 11)),
      ),
      isTrue,
    );
    expect(session.canStartWatchingAt(session.endsAt), isFalse);
  });

  test('selector prefers the nearest upcoming session', () {
    final morning = ContextFixtures.waterMorningSession(observedAt: now);
    final evening = ContextFixtures.waterEveningSession(
      observedAt: now.add(const Duration(hours: 8)),
    );

    expect(
      ShootingSessionSelector.select([evening, morning], now: now)?.kind,
      ShootingSessionKind.waterMorning,
    );
  });

  test('selector honors a requested unexpired session id', () {
    final morning = ContextFixtures.waterMorningSession(observedAt: now);
    final evening = ContextFixtures.waterEveningSession(
      observedAt: now.add(const Duration(hours: 8)),
    );

    expect(
      ShootingSessionSelector.select(
        [morning, evening],
        now: now,
        requestedId: evening.id,
      )?.id,
      evening.id,
    );
  });
}
