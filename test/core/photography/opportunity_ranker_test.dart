import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';
import 'package:luma_nest/src/core/photography/opportunity_instance.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 10);
  final scene = SceneContext(
    primaryScene: PrimaryScene.inlandWater,
    facets: const {SceneFacet.lake, SceneFacet.reflectiveSurface},
    activity: ActivityState.stationary,
  );

  test(
    'hard filters inactive tiers, unavailable core and safety conflicts',
    () {
      final ranked = OpportunityRanker.rank(
        instances: [
          _instance('session.water.evening', now),
          _instance('event.water.reflection', now),
          _instance('event.weather.rainbow', now),
        ],
        catalog: OpportunityCatalog.current,
        sceneContext: scene,
        now: now,
        activeSafetyConflicts: const {'strong-wind'},
      );

      expect(ranked, isEmpty);
    },
  );

  test('uses fixed scoring and stable tie breakers', () {
    final ranked = OpportunityRanker.rank(
      instances: [
        _instance('session.water.evening', now, id: 'instance-b'),
        _instance('session.water.morning', now, id: 'instance-a'),
      ],
      catalog: OpportunityCatalog.current,
      sceneContext: scene,
      now: now,
      preferences: const {PhotographyPreferenceId.waterCoast},
    );

    expect(ranked, hasLength(2));
    expect(ranked.first.score, 70.5);
    expect(ranked.first.instance.definitionId, 'session.water.evening');
  });

  test('rejects missing or expired required evidence', () {
    final instance = _instance(
      'session.water.evening',
      now,
      omitEvidence: EvidenceKind.wind,
    );

    final ranked = OpportunityRanker.rank(
      instances: [instance],
      catalog: OpportunityCatalog.current,
      sceneContext: scene,
      now: now,
    );

    expect(ranked, isEmpty);
  });
}

OpportunityInstance _instance(
  String definitionId,
  DateTime now, {
  String? id,
  EvidenceKind? omitEvidence,
}) {
  final definition = OpportunityCatalog.current.byId[definitionId]!;
  final expiresAt = now.add(const Duration(hours: 2));
  return OpportunityInstance(
    instanceId: id ?? 'instance-$definitionId',
    definitionId: definitionId,
    startsAt: now.subtract(const Duration(minutes: 10)),
    peaksAt: now.add(const Duration(hours: 1)),
    expiresAt: expiresAt,
    evidenceExpiresAt: now.add(const Duration(minutes: 20)),
    confidence: 0.65,
    geoScope: GeoScope.point,
    evidence: definition.requiredEvidence
        .where((kind) => kind != omitEvidence)
        .map(
          (kind) => OpportunityEvidence(
            kind: kind,
            observedAt: now,
            expiresAt: now.add(const Duration(minutes: 20)),
            confidence: 1,
            sourceId: 'test',
          ),
        ),
  );
}
