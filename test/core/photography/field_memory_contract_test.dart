import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/field_environment_selector.dart';
import 'package:luma_nest/src/core/photography/field_mode.dart';
import 'package:luma_nest/src/core/photography/opportunity_migration.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/photography/target_arrival_state.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 10);

  test('arrival assessment keeps far, approaching and arrived thresholds', () {
    final target = _target();
    expect(
      TargetArrivalStateResolver.assess(
        currentPoint: const GeoPoint(latitude: 30, longitude: 120),
        accuracyMeters: 8,
        target: target,
      )?.state,
      TargetArrivalState.arrived,
    );
    expect(
      TargetArrivalStateResolver.assess(
        currentPoint: const GeoPoint(latitude: 30.004, longitude: 120),
        accuracyMeters: 8,
        target: target,
      )?.state,
      TargetArrivalState.approaching,
    );
    expect(
      TargetArrivalStateResolver.assess(
        currentPoint: const GeoPoint(latitude: 30.02, longitude: 120),
        accuracyMeters: 8,
        target: target,
      )?.state,
      TargetArrivalState.far,
    );
    expect(
      TargetArrivalStateResolver.assess(
        currentPoint: null,
        accuracyMeters: null,
        target: target,
      ),
      isNull,
    );
  });

  test('field countdown switches precision at the ten minute boundary', () {
    final phase = ShootingSessionPhase(
      kind: ShootingPhaseKind.warmLight,
      startsAt: now,
      peaksAt: now.add(const Duration(minutes: 5)),
      endsAt: now.add(const Duration(minutes: 20)),
      conditionBand: ShootingConditionBand.good,
      directionDegrees: 258,
    );
    expect(
      FieldModeCountdown.remaining(
        phase,
        now.add(const Duration(minutes: 9, seconds: 59)),
      ),
      const Duration(minutes: 10, seconds: 1),
    );
    expect(
      FieldModeCountdown.usesSecondPrecision(
        const Duration(minutes: 10),
      ),
      isTrue,
    );
    expect(
      FieldModeCountdown.usesSecondPrecision(
        const Duration(minutes: 10, seconds: 1),
      ),
      isFalse,
    );
    expect(
      FieldModeCountdown.remaining(phase, phase.endsAt),
      Duration.zero,
    );
    final nextPhase = ShootingSessionPhase(
      kind: ShootingPhaseKind.blueHour,
      startsAt: now.add(const Duration(minutes: 20)),
      peaksAt: now.add(const Duration(minutes: 25)),
      endsAt: now.add(const Duration(minutes: 40)),
      conditionBand: ShootingConditionBand.good,
      directionDegrees: 258,
    );
    expect(
      FieldModeCountdown.remaining(
        nextPhase,
        now.add(const Duration(minutes: 10)),
      ),
      const Duration(minutes: 10),
    );
  });

  test('field selector follows water priorities and never invents factors', () {
    final session = _session(
      kind: ShootingSessionKind.waterEvening,
      factors: [
        _factor('visibility', '能见度'),
        _factor('cloud', '云量'),
        _factor('wind', '风速'),
        _factor('precipitation', '降水'),
      ],
    );
    expect(
      FieldEnvironmentSelector.select(session: session)
          .map((factor) => factor.id)
          .toList(),
      ['wind', 'precipitation', 'cloud'],
    );
  });

  test('field selector covers the core session priority families', () {
    final factors = [
      _factor('wind', '风速'),
      _factor('precipitation', '降水'),
      _factor('cloud', '云量'),
      _factor('visibility', '能见度'),
      _factor('light', '光线'),
      _factor('low_cloud', '低云'),
    ];
    final expected = <ShootingSessionKind, List<String>>{
      ShootingSessionKind.waterMorning: ['wind', 'precipitation', 'cloud'],
      ShootingSessionKind.waterEvening: ['wind', 'precipitation', 'cloud'],
      ShootingSessionKind.mountainMorning: ['low_cloud', 'cloud', 'visibility'],
      ShootingSessionKind.mountainEvening: ['low_cloud', 'cloud', 'visibility'],
      ShootingSessionKind.cityBlueHour: ['cloud', 'visibility', 'light'],
      ShootingSessionKind.cityAfterRain: ['precipitation', 'cloud', 'visibility'],
      ShootingSessionKind.desertSideLight: ['visibility', 'cloud', 'wind'],
      ShootingSessionKind.routeLightWindow: ['cloud', 'precipitation', 'visibility'],
    };
    for (final entry in expected.entries) {
      expect(
        FieldEnvironmentSelector.select(
          session: _session(kind: entry.key, factors: factors),
        ).map((factor) => factor.id).toList(),
        entry.value,
      );
    }
  });

  test('fallback only migrates to fresh reliable sessions deterministically', () {
    final primary = _session(
      id: 'primary-session',
      kind: ShootingSessionKind.waterEvening,
      trend: ShootingTrend.weakening,
    );
    final active = _session(
      id: 'active-session',
      kind: ShootingSessionKind.cityBlueHour,
      startsAt: now.subtract(const Duration(minutes: 5)),
      endsAt: now.add(const Duration(minutes: 30)),
    );
    final limited = _session(
      id: 'limited-session',
      kind: ShootingSessionKind.cityAfterRain,
      conditionBand: ShootingConditionBand.limited,
    );
    final expired = _session(
      id: 'expired-session',
      kind: ShootingSessionKind.desertSideLight,
      expiresAt: now.subtract(const Duration(minutes: 1)),
    );
    final result = ShootingOpportunityFallbackResolver.resolve(
      primary: primary,
      sessions: [limited, expired, active],
      now: now,
    );
    expect(result.alternative?.id, 'active-session');
    expect(result.reason, contains('正在减弱'));
  });

  test('stable primary does not expose a fallback', () {
    final primary = _session(id: 'stable-session');
    final result = ShootingOpportunityFallbackResolver.resolve(
      primary: primary,
      sessions: [primary, _session(id: 'other-session')],
      now: now,
    );
    expect(result.alternative, isNull);
  });
}

ShootingSession _session({
  String id = 'session-id',
  ShootingSessionKind kind = ShootingSessionKind.waterEvening,
  ShootingConditionBand conditionBand = ShootingConditionBand.good,
  ShootingConfidenceBand confidenceBand = ShootingConfidenceBand.high,
  ShootingTrend trend = ShootingTrend.stable,
  DateTime? startsAt,
  DateTime? endsAt,
  DateTime? expiresAt,
  Iterable<ShootingSessionFactor> factors = const [],
}) {
  final start = startsAt ?? DateTime.utc(2026, 9, 27, 11);
  final end = endsAt ?? start.add(const Duration(hours: 1));
  final phase = ShootingSessionPhase(
    kind: ShootingPhaseKind.warmLight,
    startsAt: start,
    peaksAt: start.add(const Duration(minutes: 15)),
    endsAt: end,
    conditionBand: conditionBand,
    directionDegrees: 258,
  );
  return ShootingSession(
    id: id,
    kind: kind,
    title: id,
    startsAt: start,
    endsAt: end,
    primaryPhase: phase.kind,
    conditionBand: conditionBand,
    confidenceBand: confidenceBand,
    trend: trend,
    phases: [phase],
    factors: factors,
    trendSamples: const [],
    targetCandidates: [_target()],
    ruleVersion: 'test.1',
    expiresAt: expiresAt ?? DateTime.utc(2026, 9, 27, 12),
  );
}

ShootingTarget _target() => ShootingTarget(
  id: 'target-id',
  name: '测试机位',
  coordinate: const GeoPoint(latitude: 30, longitude: 120),
  supportedSessions: ShootingSessionKind.values,
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

ShootingSessionFactor _factor(String id, String label) => ShootingSessionFactor(
  id: id,
  effect: ShootingFactorEffect.supporting,
  label: label,
  value: '1',
  sourceAt: DateTime.utc(2026, 9, 27, 10),
);
