import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/presentation_v2/explore/v2_region_brief_expansion.dart';

void main() {
  testWidgets('expanded exploration remains readable on compact large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final brief = _brief();
    var expanded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1000),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  V2RegionBriefExpansionCard(
                    brief: brief,
                    state: RegionBriefState(
                      status: RegionBriefLoadStatus.ready,
                      brief: brief,
                      lastExpandedAt: DateTime.utc(2026, 8, 5, 3, 20),
                    ),
                    onExpand: () => expanded = true,
                  ),
                  const SizedBox(height: 18),
                  V2RegionBriefInsightSections(insights: brief.insights),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('扩展探索'), findsOneWidget);
    expect(find.textContaining('历史脉络'), findsOneWidget);
    expect(find.text('2 个来源'), findsOneWidget);
    expect(find.text('1 个高等级来源'), findsOneWidget);
    expect(find.text('1 条已核验'), findsOneWidget);

    await tester.tap(find.byKey(const Key('v2-expand-region-brief')));
    await tester.pump();
    expect(expanded, isTrue);

    await tester.scrollUntilVisible(
      find.text('出发前确认'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('适合拍什么'), findsOneWidget);
    expect(find.text('正在发生'), findsOneWidget);
    expect(find.text('这里的味道与人文'), findsOneWidget);
    expect(find.text('出发前确认'), findsOneWidget);
    expect(find.text('多源核验'), findsOneWidget);
    expect(find.text('待核实'), findsOneWidget);
    expect(find.text('单一来源'), findsOneWidget);
    expect(find.text('来源冲突'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expansion progress exposes active missions and disables action', (
    tester,
  ) async {
    final brief = _brief(
      missions: const ['地方活动', '人文资料'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: V2RegionBriefExpansionCard(
            brief: brief,
            state: RegionBriefState(
              status: RegionBriefLoadStatus.refreshing,
              brief: brief,
              manualExpansion: true,
            ),
            onExpand: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在扩展探索'), findsOneWidget);
    expect(find.text('正在处理：地方活动、人文资料'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('v2-expand-region-brief')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

RegionBrief _brief({List<String> missions = const []}) {
  final now = DateTime.utc(2026, 8, 5, 3);
  final profile = ExplorationSceneProfile(
    physicalScene: PrimaryScene.urban,
    facets: const {SceneFacet.architecture, SceneFacet.oldTown},
    settlement: SettlementType.historicTown,
    remoteness: RemotenessLevel.connected,
    altitude: AltitudeBand.low,
    poiDensity: PoiDensityBand.normal,
    mobility: ActivityState.walking,
    routeStage: ContextRouteStage.none,
  );
  final sources = [
    InsightEvidence(
      id: 'source-official',
      sourcePolicyId: 'official-cultural-bureau',
      publisher: '当地文化部门',
      title: '区域资料',
      url: Uri.parse('https://example.gov/region'),
      observedAt: now,
      qualityTier: InsightQualityTier.s,
      license: 'public-record',
      version: '2026-08-05',
    ),
    InsightEvidence(
      id: 'source-local',
      sourcePolicyId: 'reviewed-local-source',
      publisher: '地方资料库',
      title: '地方活动资料',
      url: Uri.parse('https://example.org/local'),
      observedAt: now,
      qualityTier: InsightQualityTier.b,
      license: 'reviewed-reference',
      version: '2026-08-05',
    ),
  ];
  final insights = [
    _insight(
      now: now,
      id: 'photo',
      type: RegionInsightType.photographyTheme,
      title: '街巷与传统建筑',
      verification: InsightVerificationState.corroborated,
      evidenceIds: const ['source-official', 'source-local'],
    ),
    _insight(
      now: now,
      id: 'event',
      type: RegionInsightType.event,
      title: '周末地方演出',
      verification: InsightVerificationState.candidate,
      evidenceIds: const ['source-local'],
      timeSensitive: true,
    ),
    _insight(
      now: now,
      id: 'food',
      type: RegionInsightType.localFood,
      title: '地方小吃',
      verification: InsightVerificationState.singleSource,
      evidenceIds: const ['source-local'],
    ),
    _insight(
      now: now,
      id: 'regulation',
      type: RegionInsightType.regulation,
      title: '部分区域拍摄限制待确认',
      verification: InsightVerificationState.conflicting,
      evidenceIds: const ['source-official', 'source-local'],
      timeSensitive: true,
    ),
  ];
  return RegionBrief(
    id: 'brief-historic-town',
    regionId: 'historic-town',
    regionName: '测试古镇',
    profile: profile,
    generatedAt: now,
    expiresAt: now.add(const Duration(hours: 6)),
    status: RegionBriefStatus.ready,
    completeness: RegionBriefCompleteness.comprehensive,
    identity: FactBoundText(
      summary: '历史街区',
      factIds: const ['fact-photo'],
    ),
    orientation: FactBoundText(
      summary: '核心街巷位于河道两侧',
      factIds: const ['fact-photo'],
    ),
    photoThemes: const [
      RegionPhotoTheme(id: 'architecture', label: '传统建筑'),
    ],
    insights: insights,
    sources: sources,
    refresh: RegionBriefRefresh(
      refreshingMissions: missions,
      retryAfter: null,
    ),
  );
}

RegionInsight _insight({
  required DateTime now,
  required String id,
  required RegionInsightType type,
  required String title,
  required InsightVerificationState verification,
  required List<String> evidenceIds,
  bool timeSensitive = false,
}) => RegionInsight(
  id: id,
  regionId: 'historic-town',
  type: type,
  title: title,
  summary: '$title的事实摘要。',
  verification: verification,
  factIds: ['fact-$id'],
  evidenceIds: evidenceIds,
  observedAt: now,
  expiresAt: now.add(const Duration(hours: 6)),
  timeSensitive: timeSensitive,
  actionability: InsightActionability.detail,
);
