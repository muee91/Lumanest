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
    insights: const [],
    sources: const [],
    refresh: RegionBriefRefresh(
      refreshingMissions: const [],
      retryAfter: status == RegionBriefStatus.pending
          ? const Duration(seconds: 10)
          : null,
    ),
  );
}
