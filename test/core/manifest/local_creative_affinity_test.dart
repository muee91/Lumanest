import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/manifest/local_creative_affinity.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

void main() {
  test('uses session kinds and decays older recorded outcomes', () {
    final now = DateTime.utc(2026, 7, 17, 12);
    final water = ContextFixtures.waterEveningSession(observedAt: now);
    final mountain = ShootingSession(
      id: 'session_aaaaaaaaaaaaaaaaaaaaaaaa',
      kind: ShootingSessionKind.mountainEvening,
      title: '山地晚光',
      startsAt: now,
      endsAt: now.add(const Duration(hours: 1)),
      primaryPhase: ShootingPhaseKind.warmLight,
      conditionBand: ShootingConditionBand.good,
      confidenceBand: ShootingConfidenceBand.high,
      trend: ShootingTrend.stable,
      phases: [
        ShootingSessionPhase(
          kind: ShootingPhaseKind.warmLight,
          startsAt: now,
          peaksAt: now.add(const Duration(minutes: 20)),
          endsAt: now.add(const Duration(hours: 1)),
          conditionBand: ShootingConditionBand.good,
          directionDegrees: 270,
        ),
      ],
      factors: const [],
      trendSamples: const [],
      targetCandidates: const [],
      ruleVersion: 'mountain-evening.1',
      expiresAt: now.add(const Duration(minutes: 15)),
    );
    final affinity = LocalCreativeAffinity.fromResults([
      ShootingSessionResult.record(
        session: water,
        snapshotId: 'ctx',
        outcome: ShootingSessionOutcome.captured,
        recordedAt: now,
      ),
      ShootingSessionResult.record(
        session: mountain,
        snapshotId: 'ctx',
        outcome: ShootingSessionOutcome.conditionsDidNotAppear,
        recordedAt: DateTime.utc(2026, 1, 1),
      ),
    ], now: now);

    expect(affinity['session.water.evening'], greaterThan(0));
    expect(affinity['session.mountain.evening'], lessThan(0));
  });
}
