import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/application/region_discovery_highlight.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22, 2);

  test('selects a verified actionable regional finding', () {
    final brief = _brief(
      now,
      insights: [
        _insight(
          now,
          id: 'event_1',
          title: '今晚有地方戏演出',
          verification: InsightVerificationState.authoritative,
          actionability: InsightActionability.remind,
          timeSensitive: true,
        ),
      ],
    );

    final highlight = selectRegionDiscoveryHighlight(brief, now: now);

    expect(highlight?.regionName, '海宁');
    expect(highlight?.title, '今晚有地方戏演出');
    expect(highlight?.timeSensitive, isTrue);
  });

  test('hides candidate, conflicting, expired and identity-only findings', () {
    final brief = _brief(
      now,
      insights: [
        _insight(
          now,
          id: 'candidate',
          title: '社区传闻',
          verification: InsightVerificationState.candidate,
          actionability: InsightActionability.detail,
        ),
        _insight(
          now,
          id: 'identity',
          title: '区域身份',
          verification: InsightVerificationState.authoritative,
          actionability: InsightActionability.detail,
          type: RegionInsightType.areaIdentity,
        ),
        _insight(
          now,
          id: 'expired',
          title: '已过期活动',
          verification: InsightVerificationState.authoritative,
          actionability: InsightActionability.remind,
          expiresAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
    );

    expect(selectRegionDiscoveryHighlight(brief, now: now), isNull);
  });
}

RegionBrief _brief(DateTime now, {required List<RegionInsight> insights}) =>
    RegionBrief(
      id: 'brief_1',
      regionId: 'g1:1',
      regionName: '海宁',
      profile: ExplorationSceneProfile(
        physicalScene: PrimaryScene.urban,
        facets: const {SceneFacet.architecture},
        settlement: SettlementType.urbanDistrict,
        remoteness: RemotenessLevel.connected,
        altitude: AltitudeBand.low,
        poiDensity: PoiDensityBand.dense,
        mobility: ActivityState.stationary,
        routeStage: ContextRouteStage.none,
      ),
      generatedAt: now,
      expiresAt: now.add(const Duration(hours: 6)),
      status: RegionBriefStatus.ready,
      completeness: RegionBriefCompleteness.actionable,
      identity: FactBoundText(summary: '海宁区域资料', factIds: const ['fact_1']),
      orientation: FactBoundText(summary: '核心区在附近', factIds: const ['fact_2']),
      photoThemes: const [],
      insights: insights,
      sources: [
        InsightEvidence(
          id: 'source_1',
          sourcePolicyId: 'official',
          publisher: '官方来源',
          title: '区域资料',
          url: Uri.parse('https://example.gov.cn/region'),
          observedAt: now,
          qualityTier: InsightQualityTier.s,
          license: 'public',
          version: '1',
        ),
      ],
      refresh: RegionBriefRefresh(
        refreshingMissions: const [],
        retryAfter: null,
      ),
    );

RegionInsight _insight(
  DateTime now, {
  required String id,
  required String title,
  required InsightVerificationState verification,
  required InsightActionability actionability,
  bool timeSensitive = false,
  DateTime? expiresAt,
  RegionInsightType type = RegionInsightType.event,
}) => RegionInsight(
  id: id,
  regionId: 'g1:1',
  type: type,
  title: title,
  summary: '内容经来源验证。',
  verification: verification,
  factIds: ['$id-fact'],
  evidenceIds: const ['source_1'],
  observedAt: now,
  expiresAt: expiresAt ?? now.add(const Duration(hours: 2)),
  timeSensitive: timeSensitive,
  actionability: actionability,
);
