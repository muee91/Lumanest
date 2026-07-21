import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/infrastructure/drift_region_brief_cache.dart';

void main() {
  test(
    'round-trips only a current Region Brief for the same coarse grid',
    () async {
      final database = AppDatabase.inMemory();
      final now = DateTime.utc(2026, 7, 21, 12);
      final cache = DriftRegionBriefCache(database, now: () => now);
      final key = RegionBriefCacheKey.forPoint(
        const GeoPoint(latitude: 30.21, longitude: 120.11),
        locale: 'zh-CN',
      );
      final brief = _brief(
        regionId: key.regionKey,
        generatedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );

      await cache.write(key, brief);

      expect((await cache.read(key))?.identity?.summary, '沿河保留传统街巷。');
      expect(
        await cache.read(
          RegionBriefCacheKey.forPoint(
            const GeoPoint(latitude: 30.31, longitude: 120.11),
            locale: 'zh-CN',
          ),
        ),
        isNull,
      );
      await database.close();
    },
  );

  test('does not restore an expired Region Brief', () async {
    final database = AppDatabase.inMemory();
    final now = DateTime.utc(2026, 7, 21, 12);
    final key = RegionBriefCacheKey.forPoint(
      const GeoPoint(latitude: 30.21, longitude: 120.11),
      locale: 'zh-CN',
    );
    final cache = DriftRegionBriefCache(
      database,
      now: () => now.add(const Duration(hours: 2)),
    );
    await cache.write(
      key,
      _brief(
        regionId: key.regionKey,
        generatedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    );

    expect(await cache.read(key), isNull);
    await database.close();
  });
}

RegionBrief _brief({
  required String regionId,
  required DateTime generatedAt,
  required DateTime expiresAt,
}) {
  final source = InsightEvidence(
    id: 'source_1',
    sourcePolicyId: 'official-culture',
    publisher: '地方文旅局',
    title: '古镇介绍',
    url: Uri.parse('https://culture.example.gov.cn/town'),
    observedAt: DateTime.utc(2026, 7, 21),
    qualityTier: InsightQualityTier.a,
    license: 'CC BY 4.0',
    version: '2026-07',
  );
  RegionInsight insight(String id, RegionInsightType type, String factId) =>
      RegionInsight(
        id: id,
        regionId: regionId,
        type: type,
        title: type == RegionInsightType.areaIdentity ? '示例古镇' : '核心街区方向',
        summary: type == RegionInsightType.areaIdentity
            ? '沿河保留传统街巷。'
            : '核心街区在北侧。',
        verification: InsightVerificationState.singleSource,
        factIds: [factId],
        evidenceIds: const ['source_1'],
        observedAt: generatedAt,
        expiresAt: expiresAt,
        timeSensitive: false,
        actionability: InsightActionability.detail,
      );
  return RegionBrief(
    id: 'brief_1',
    regionId: regionId,
    regionName: '示例古镇',
    profile: ExplorationSceneProfile(
      physicalScene: PrimaryScene.urban,
      facets: const {SceneFacet.oldTown},
      settlement: SettlementType.historicDistrict,
      remoteness: RemotenessLevel.unknown,
      altitude: AltitudeBand.unknown,
      poiDensity: PoiDensityBand.unknown,
      mobility: ActivityState.walking,
      routeStage: ContextRouteStage.none,
    ),
    generatedAt: generatedAt,
    expiresAt: expiresAt,
    status: RegionBriefStatus.ready,
    completeness: RegionBriefCompleteness.partial,
    identity: FactBoundText(summary: '沿河保留传统街巷。', factIds: const ['fact_1']),
    orientation: FactBoundText(summary: '核心街区在北侧。', factIds: const ['fact_2']),
    photoThemes: const [],
    insights: [
      insight('insight_1', RegionInsightType.areaIdentity, 'fact_1'),
      insight('insight_2', RegionInsightType.orientation, 'fact_2'),
    ],
    sources: [source],
    refresh: RegionBriefRefresh(refreshingMissions: const [], retryAfter: null),
  );
}
