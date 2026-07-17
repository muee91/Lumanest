import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';

void main() {
  final now = DateTime.utc(2026, 7, 17, 11);

  PhotographyOpportunity opportunity({
    DateTime? startsAt,
    DateTime? expiresAt,
    double confidence = .9,
    bool atCurrentLocation = false,
    bool returnJourney = false,
    Iterable<String> requiredCapabilities = const <String>[],
  }) => PhotographyOpportunity(
    id: 'sunset',
    title: '晚霞窗口',
    startsAt: startsAt ?? now,
    peaksAt:
        (expiresAt ?? now.add(const Duration(minutes: 40))).isBefore(
          (startsAt ?? now).add(const Duration(minutes: 15)),
        )
        ? (expiresAt ?? now.add(const Duration(minutes: 40)))
        : (startsAt ?? now).add(const Duration(minutes: 15)),
    expiresAt: expiresAt ?? now.add(const Duration(minutes: 40)),
    confidence: confidence,
    requiredCapabilities: requiredCapabilities,
    isAtCurrentLocation: atCurrentLocation,
    isReturnJourney: returnJourney,
    evidence: const [
      PhotographyEvidence(
        id: 'clouds',
        kind: PhotographyEvidenceKind.weather,
        statement: '云层变化已成立。',
        confidence: .8,
      ),
    ],
  );

  test('resolves a current, equipped opportunity as go', () {
    final result = PhotographyDecisionResolver.resolve(opportunity(), now: now);

    expect(result.decision, PhotographyDecision.go);
    expect(result.actionLabel, '立即出发');
    expect(result.score, greaterThanOrEqualTo(70));
  });

  test('resolves a future opportunity as wait without changing its facts', () {
    final result = PhotographyDecisionResolver.resolve(
      opportunity(startsAt: now.add(const Duration(minutes: 20))),
      now: now,
    );

    expect(result.decision, PhotographyDecision.wait);
    expect(result.actionLabel, '开始守候');
  });

  test('resolves an active opportunity at the current place as stay', () {
    final result = PhotographyDecisionResolver.resolve(
      opportunity(atCurrentLocation: true),
      now: now,
    );

    expect(result.decision, PhotographyDecision.stay);
    expect(result.actionLabel, '就地拍摄');
  });

  test('resolves missing required equipment as move and exposes only IDs', () {
    final result = PhotographyDecisionResolver.resolve(
      opportunity(requiredCapabilities: const ['tripod']),
      now: now,
    );

    expect(result.decision, PhotographyDecision.move);
    expect(result.missingCapabilities, ['tripod']);
  });

  test('prioritizes return at the end of a return journey', () {
    final result = PhotographyDecisionResolver.resolve(
      opportunity(
        returnJourney: true,
        expiresAt: now.add(const Duration(minutes: 10)),
      ),
      now: now,
    );

    expect(result.decision, PhotographyDecision.returnHome);
  });

  test('expired or weak opportunities are skipped', () {
    expect(
      PhotographyDecisionResolver.resolve(
        opportunity(expiresAt: now),
        now: now,
      ).decision,
      PhotographyDecision.skip,
    );
    expect(
      PhotographyDecisionResolver.resolve(
        opportunity(confidence: .1),
        now: now,
      ).decision,
      PhotographyDecision.skip,
    );
  });

  test('value objects retain immutable evidence and requirements', () {
    final evidence = <PhotographyEvidence>[
      const PhotographyEvidence(
        id: 'sun',
        kind: PhotographyEvidenceKind.light,
        statement: '低角度光线已成立。',
        confidence: .7,
      ),
    ];
    final requirements = <String>{'tripod'};
    final value = PhotographyOpportunity(
      id: 'test',
      title: '测试',
      startsAt: now,
      peaksAt: now,
      expiresAt: now.add(const Duration(minutes: 1)),
      confidence: .7,
      evidence: evidence,
      requiredCapabilities: requirements,
    );
    evidence.clear();
    requirements.clear();

    expect(value.evidence, hasLength(1));
    expect(value.requiredCapabilities, {'tripod'});
    expect(
      () => value.evidence.add(
        const PhotographyEvidence(
          id: 'later',
          kind: PhotographyEvidenceKind.light,
          statement: 'later',
          confidence: .2,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('target and route-corridor changes participate in value equality', () {
    final target = PhotographyTarget(
      id: 'target_123',
      name: '湖东岸',
      kind: PhotographyTargetKind.lakeshore,
      coordinate: const GeoPoint(latitude: 30.1, longitude: 120.2),
      arrivalDeadline: now.add(const Duration(minutes: 20)),
    );
    final corridor = PhotographyCorridor(
      routeId: 'route_123',
      observations: [
        PhotographyCorridorObservation(
          progress: .5,
          expectedAt: now.add(const Duration(minutes: 12)),
          condition: 'cloudy',
          windSpeedMps: 2.2,
          precipitationMm: 0,
          thunder: false,
          opportunityId: 'sunset',
        ),
      ],
    );
    final base = opportunity();
    final targeted = PhotographyOpportunity(
      id: 'sunset',
      title: '晚霞窗口',
      startsAt: now,
      peaksAt: now.add(const Duration(minutes: 15)),
      expiresAt: now.add(const Duration(minutes: 40)),
      confidence: .9,
      target: target,
      evidence: const [
        PhotographyEvidence(
          id: 'clouds',
          kind: PhotographyEvidenceKind.weather,
          statement: '云层变化已成立。',
          confidence: .8,
        ),
      ],
    );
    final routed = PhotographyOpportunity(
      id: 'sunset',
      title: '晚霞窗口',
      startsAt: now,
      peaksAt: now.add(const Duration(minutes: 15)),
      expiresAt: now.add(const Duration(minutes: 40)),
      confidence: .9,
      corridor: corridor,
      evidence: const [
        PhotographyEvidence(
          id: 'clouds',
          kind: PhotographyEvidenceKind.weather,
          statement: '云层变化已成立。',
          confidence: .8,
        ),
      ],
    );

    expect(targeted, isNot(base));
    expect(routed, isNot(base));
    expect(targeted.hashCode, isNot(base.hashCode));
    expect(routed.hashCode, isNot(base.hashCode));
  });
}
