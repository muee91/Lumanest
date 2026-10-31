import 'dart:async';

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

/// A manual refresh that is still in flight when the controller rebuilds -
/// or when a newer overlapping refresh completes - must not commit its answer.
/// The generation counter plus `ref.mounted` are the only things standing
/// between a stale response and the state; these tests fail if either guard
/// is removed.
void main() {
  test('an in-flight manual refresh cannot commit after the controller rebuilds',
      () {
    fakeAsync((async) {
      final repository = _GatedRepository();
      final container = _container(repository);
      addTearDown(container.dispose);

      // The automatic load fires first; its answer is held back.
      container.read(regionBriefControllerProvider);
      async.flushMicrotasks();
      expect(repository.pending, greaterThanOrEqualTo(1));

      container.read(regionBriefControllerProvider.notifier).load(manual: true);
      async.flushMicrotasks();

      // A rebuild (snapshot/profile change) advances the generation; the
      // rebuild fires its own load, which answers with the fresh brief.
      container.invalidate(regionBriefControllerProvider);
      // Invalidation rebuilds lazily; the read stands in for the listener
      // that a live Explore page would provide.
      container.read(regionBriefControllerProvider);
      async.flushMicrotasks();
      repository.completeLast(_usableBrief('fresh-brief'));
      async.flushMicrotasks();
      expect(
        container.read(regionBriefControllerProvider).brief?.id,
        'fresh-brief',
      );

      // Only now do every older generation answer - the in-flight manual
      // refresh among them. None of them may commit.
      repository.completeAllRemaining(_usableBrief('stale-brief'));
      async.flushMicrotasks();

      expect(
        container.read(regionBriefControllerProvider).brief?.id,
        'fresh-brief',
        reason: 'an invalidated generation must not commit',
      );
    });
  });

  test('an older overlapping manual refresh loses to the newer one', () {
    fakeAsync((async) {
      final repository = _GatedRepository();
      final container = _container(repository);
      addTearDown(container.dispose);

      container.read(regionBriefControllerProvider);
      async.flushMicrotasks();

      final notifier = container.read(regionBriefControllerProvider.notifier);
      unawaited(notifier.load(manual: true));
      async.flushMicrotasks();
      unawaited(notifier.load(manual: true));
      async.flushMicrotasks();
      expect(repository.pending, greaterThanOrEqualTo(2));

      // The newer refresh lands first, then every older generation arrives.
      repository.completeLast(_usableBrief('newer-brief'));
      async.flushMicrotasks();
      expect(
        container.read(regionBriefControllerProvider).brief?.id,
        'newer-brief',
      );
      repository.completeAllRemaining(_usableBrief('older-brief'));
      async.flushMicrotasks();

      expect(
        container.read(regionBriefControllerProvider).brief?.id,
        'newer-brief',
        reason: 'the older overlapping refresh must not win',
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

RegionBrief _usableBrief(String id) {
  final now = DateTime.utc(2026, 11, 1, 8);
  return RegionBrief(
    id: id,
    regionId: 'region-1',
    regionName: 'region-1',
    profile: _profile(),
    generatedAt: now,
    expiresAt: now.add(const Duration(hours: 6)),
    status: RegionBriefStatus.ready,
    completeness: RegionBriefCompleteness.actionable,
    identity: FactBoundText(
      summary: '沿河保留传统街巷。',
      factIds: const ['fact_1'],
    ),
    orientation: FactBoundText(
      summary: '核心街区在北侧。',
      factIds: const ['fact_2'],
    ),
    photoThemes: const [],
    insights: const [],
    sources: const [],
    refresh: RegionBriefRefresh(refreshingMissions: const [], retryAfter: null),
  );
}

class _GatedRepository implements RegionBriefRepository {
  final List<Completer<RegionBrief>> _pending = [];

  int get pending => _pending.length;

  @override
  Future<RegionBrief> fetch(RegionBriefRequest request) {
    final completer = Completer<RegionBrief>();
    _pending.add(completer);
    return completer.future;
  }

  // Fetches are queued in generation order, so the last one belongs to the
  // most recent load.
  void completeLast(RegionBrief brief) {
    _pending.removeLast().complete(brief);
  }

  void completeAllRemaining(RegionBrief brief) {
    while (_pending.isNotEmpty) {
      _pending.removeAt(0).complete(brief);
    }
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
