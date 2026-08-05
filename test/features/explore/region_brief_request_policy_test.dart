import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_request_policy.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

void main() {
  test('automatic request stays lightweight and local', () {
    final plan = RegionBriefRequestPolicy.plan(
      _profile(settlement: SettlementType.historicTown),
      manual: false,
    );

    expect(plan.activationType, 'foreground_opportunistic');
    expect(plan.radiusMeters, 5000);
    expect(plan.requestedSections, const [
      'identity',
      'orientation',
      'photoThemes',
      'practical',
    ]);
  });

  test('manual expansion requests the full regional brief', () {
    final plan = RegionBriefRequestPolicy.plan(
      _profile(settlement: SettlementType.historicTown),
      manual: true,
    );

    expect(plan.activationType, 'user_manual');
    expect(plan.radiusMeters, 15000);
    expect(plan.requestedSections, const [
      'identity',
      'orientation',
      'photoThemes',
      'happeningNow',
      'places',
      'localTaste',
      'etiquette',
      'practical',
    ]);
  });

  test('driving expansion is wider while remote requests remain bounded', () {
    final driving = _profile(mobility: ActivityState.driving);
    expect(
      RegionBriefRequestPolicy.radiusFor(driving, expanded: false),
      20000,
    );
    expect(
      RegionBriefRequestPolicy.radiusFor(driving, expanded: true),
      35000,
    );

    final remote = _profile(remoteness: RemotenessLevel.remote);
    expect(
      RegionBriefRequestPolicy.radiusFor(remote, expanded: false),
      50000,
    );
    expect(
      RegionBriefRequestPolicy.radiusFor(remote, expanded: true),
      50000,
    );
  });

  test('pending manual expansion preserves the existing usable brief', () {
    final existing = _brief(
      regionId: 'hangzhou',
      completeness: RegionBriefCompleteness.actionable,
    );
    final pending = _brief(
      regionId: 'hangzhou',
      status: RegionBriefStatus.pending,
      completeness: RegionBriefCompleteness.identityOnly,
      usable: false,
    );

    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: existing,
        incoming: pending,
        manual: true,
      ),
      isTrue,
    );
  });

  test('lightweight refresh cannot downgrade an expanded result', () {
    final expanded = _brief(
      regionId: 'hangzhou',
      completeness: RegionBriefCompleteness.comprehensive,
    );
    final lightweight = _brief(
      regionId: 'hangzhou',
      completeness: RegionBriefCompleteness.partial,
    );

    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: expanded,
        incoming: lightweight,
        manual: false,
      ),
      isTrue,
    );
  });


  test('verification targets only weak evidence sections and stays bounded', () {
    final brief = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.event, verification: InsightVerificationState.candidate, timeSensitive: true),
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.conflicting, timeSensitive: true),
        _insight(type: RegionInsightType.localFood, verification: InsightVerificationState.singleSource),
        _insight(type: RegionInsightType.architecture, verification: InsightVerificationState.corroborated),
      ],
    );

    expect(RegionBriefRequestPolicy.needsVerification(brief), isTrue);
    expect(RegionBriefRequestPolicy.verificationTargetCount(brief), 2);
    expect(
      RegionBriefRequestPolicy.verificationSections(brief),
      const ['practical', 'happeningNow'],
    );
    final plan = RegionBriefRequestPolicy.verificationPlan(
      _profile(settlement: SettlementType.historicTown),
      brief,
    );
    expect(plan.activationType, 'ai_verification');
    expect(plan.radiusMeters, 15000);
    expect(plan.requestedSections, const ['practical', 'happeningNow']);
  });

  test('verification adopts a real evidence improvement', () {
    final previous = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.conflicting, timeSensitive: true),
      ],
      sourceCount: 2,
    );
    final incoming = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.corroborated, timeSensitive: true),
      ],
      sourceCount: 2,
    );

    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: previous,
        incoming: incoming,
        manual: false,
        verification: true,
      ),
      isFalse,
    );
  });

  test('verification cannot improve by deleting weak facts or sources', () {
    final previous = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.event, verification: InsightVerificationState.candidate, timeSensitive: true),
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.conflicting, timeSensitive: true),
      ],
      sourceCount: 2,
    );
    final incoming = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.event, verification: InsightVerificationState.corroborated, timeSensitive: true),
      ],
      sourceCount: 1,
    );

    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: previous,
        incoming: incoming,
        manual: false,
        verification: true,
      ),
      isTrue,
    );
  });

  test('a different region replaces the previous brief normally', () {
    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: _brief(regionId: 'hangzhou'),
        incoming: _brief(regionId: 'huzhou'),
        manual: false,
      ),
      isFalse,
    );
  });
}

ExplorationSceneProfile _profile({
  SettlementType settlement = SettlementType.urbanDistrict,
  RemotenessLevel remoteness = RemotenessLevel.connected,
  ActivityState mobility = ActivityState.stationary,
}) => ExplorationSceneProfile(
  physicalScene: PrimaryScene.urban,
  facets: const {SceneFacet.architecture},
  settlement: settlement,
  remoteness: remoteness,
  altitude: AltitudeBand.low,
  poiDensity: PoiDensityBand.dense,
  mobility: mobility,
  routeStage: ContextRouteStage.none,
);

RegionBrief _brief({
  required String regionId,
  RegionBriefStatus status = RegionBriefStatus.ready,
  RegionBriefCompleteness completeness = RegionBriefCompleteness.actionable,
  bool usable = true,
  List<RegionInsight> insights = const [],
  int sourceCount = 0,
}) {
  final now = DateTime.utc(2026, 8, 5, 3);
  return RegionBrief(
    id: 'brief-$regionId',
    regionId: regionId,
    regionName: regionId,
    profile: _profile(),
    generatedAt: now,
    expiresAt: now.add(const Duration(hours: 6)),
    status: status,
    completeness: completeness,
    identity: usable
        ? FactBoundText(summary: '区域身份', factIds: const ['fact-1'])
        : null,
    orientation: usable
        ? FactBoundText(summary: '方向信息', factIds: const ['fact-1'])
        : null,
    photoThemes: const [],
    insights: insights,
    sources: List.generate(
      sourceCount,
      (index) => InsightEvidence(
        id: 'source-$index',
        sourcePolicyId: 'policy-$index',
        publisher: 'Publisher $index',
        title: 'Source $index',
        url: Uri.parse('https://example.org/$index'),
        observedAt: now,
        qualityTier: index == 0 ? InsightQualityTier.a : InsightQualityTier.b,
        license: 'reviewed',
        version: '1',
      ),
    ),
    refresh: RegionBriefRefresh(
      refreshingMissions: const [],
      retryAfter: status == RegionBriefStatus.pending
          ? const Duration(seconds: 10)
          : null,
    ),
  );
}


RegionInsight _insight({
  required RegionInsightType type,
  required InsightVerificationState verification,
  bool timeSensitive = false,
}) {
  final now = DateTime.utc(2026, 8, 5, 3);
  return RegionInsight(
    id: '${type.name}-${verification.name}',
    regionId: 'hangzhou',
    type: type,
    title: type.name,
    summary: '事实摘要',
    verification: verification,
    factIds: const ['fact'],
    evidenceIds: const ['source-0'],
    observedAt: now,
    expiresAt: now.add(const Duration(hours: 6)),
    timeSensitive: timeSensitive,
    actionability: InsightActionability.detail,
  );
}
