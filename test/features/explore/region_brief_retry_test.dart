import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/application/exploration_scene_profile_resolver.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/drift_region_brief_cache.dart';

/// The retry timer used to call the public `load`, which zeroes the retry
/// budget whenever the entry was user-initiated. A manual expansion against a
/// Broker that keeps answering `pending` therefore reset the ceiling on every
/// repeat and the client polled forever. These tests pin the ceiling on the
/// manual path, which is the only path that ever had the defect.
void main() {
  test('a manual expansion retries a bounded number of times', () {
    fakeAsync((async) {
      final repository = _PendingRepository();
      final container = _container(repository);
      addTearDown(container.dispose);

      container.read(regionBriefControllerProvider);
      async.elapse(const Duration(minutes: 2));
      final afterAutomatic = repository.calls;

      container.read(regionBriefControllerProvider.notifier).load(manual: true);
      async.elapse(const Duration(minutes: 2));
      final bounded = repository.calls;

      // Ten more minutes is many retry windows. Before the fix each repeat
      // re-entered `load`, reset the budget, and the counter kept climbing.
      async.elapse(const Duration(minutes: 10));

      expect(
        repository.calls,
        bounded,
        reason: '到达上限后不应再发起任何自动重试',
      );
      expect(
        bounded - afterAutomatic,
        lessThanOrEqualTo(5),
        reason: '手动入口本身 + 最多 4 次自动重试',
      );
    });
  });

  test('a fresh manual expansion after the ceiling is reached polls again', () {
    fakeAsync((async) {
      final repository = _PendingRepository();
      final container = _container(repository);
      addTearDown(container.dispose);

      container.read(regionBriefControllerProvider);
      container.read(regionBriefControllerProvider.notifier).load(manual: true);
      async.elapse(const Duration(minutes: 5));
      final exhausted = repository.calls;

      // The user taps again: this is a new intent and gets a new budget.
      container.read(regionBriefControllerProvider.notifier).load(manual: true);
      async.elapse(const Duration(minutes: 2));

      expect(
        repository.calls,
        greaterThan(exhausted),
        reason: '用户主动扩展后应重新获得重试预算',
      );
    });
  });
}

ProviderContainer _container(RegionBriefRepository repository) {
  return ProviderContainer(
    overrides: [
      environmentSnapshotProvider.overrideWith(_FixedEnvironmentController.new),
      explorationSceneProfileProvider.overrideWith((ref) async => _profile()),
      regionBriefRepositoryProvider.overrideWithValue(repository),
      regionBriefCacheProvider.overrideWithValue(_EmptyCache()),
    ],
  );
}

ExplorationSceneProfile _profile() => ExplorationSceneProfile(
  physicalScene: PrimaryScene.urban,
  facets: {SceneFacet.oldTown},
  settlement: SettlementType.historicDistrict,
  remoteness: RemotenessLevel.unknown,
  altitude: AltitudeBand.low,
  poiDensity: PoiDensityBand.unknown,
  mobility: ActivityState.stationary,
  routeStage: ContextRouteStage.none,
);

class _PendingRepository implements RegionBriefRepository {
  int calls = 0;

  @override
  Future<RegionBrief> fetch(RegionBriefRequest request) async {
    calls += 1;
    final now = DateTime.now().toUtc();
    return RegionBrief(
      id: 'brief-pending',
      regionId: 'region-1',
      regionName: 'region-1',
      profile: _profile(),
      generatedAt: now,
      expiresAt: now.add(const Duration(hours: 6)),
      status: RegionBriefStatus.pending,
      completeness: RegionBriefCompleteness.identityOnly,
      photoThemes: const [],
      insights: const [],
      sources: const [],
      refresh: RegionBriefRefresh(
        refreshingMissions: const ['identity'],
        // Five seconds is the floor the controller applies, so a short delay
        // keeps the test bounded while still exercising the timer path.
        retryAfter: const Duration(seconds: 5),
      ),
    );
  }
}

class _EmptyCache implements RegionBriefLocalCache {
  @override
  Future<RegionBrief?> read(RegionBriefCacheKey key) async => null;

  @override
  Future<void> write(RegionBriefCacheKey key, RegionBrief brief) async {}

  @override
  Future<void> clear() async {}
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() async => ContextFixtures.lakeSunset();
}
