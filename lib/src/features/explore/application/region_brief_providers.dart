import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/explore/application/exploration_scene_profile_resolver.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_region_brief_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/drift_region_brief_cache.dart';

enum RegionBriefLoadStatus { idle, loading, refreshing, ready, degraded, error }

class RegionBriefState {
  const RegionBriefState({required this.status, this.brief, this.errorCode});

  const RegionBriefState.idle() : this(status: RegionBriefLoadStatus.idle);

  final RegionBriefLoadStatus status;
  final RegionBrief? brief;
  final String? errorCode;

  bool get hasUsableBrief => brief?.hasUsableFacts == true;
}

final regionBriefRepositoryProvider = Provider<RegionBriefRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return DataBrokerRegionBriefRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioRegionBriefTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 8),
        ),
      ),
    ),
  );
});

final regionBriefCacheProvider = Provider<RegionBriefLocalCache>((ref) {
  return DriftRegionBriefCache(ref.watch(appDatabaseProvider));
});

class RegionBriefController extends Notifier<RegionBriefState> {
  static const _maximumAutomaticRetries = 4;

  int _generation = 0;
  int _automaticRetries = 0;
  Timer? _retryTimer;

  @override
  RegionBriefState build() {
    _retryTimer?.cancel();
    _automaticRetries = 0;
    ref.onDispose(() => _retryTimer?.cancel());
    ref.watch(environmentSnapshotProvider);
    ref.watch(explorationSceneProfileProvider);
    unawaited(load());
    return const RegionBriefState.idle();
  }

  Future<void> load({bool manual = false}) async {
    _retryTimer?.cancel();
    if (manual) _automaticRetries = 0;
    final generation = ++_generation;
    var previous = state.brief;
    state = RegionBriefState(
      status: previous == null
          ? RegionBriefLoadStatus.loading
          : RegionBriefLoadStatus.refreshing,
      brief: previous,
    );
    try {
      final snapshot = await ref.read(environmentSnapshotProvider.future);
      final profile = await ref.read(explorationSceneProfileProvider.future);
      final location = snapshot.location;
      if (location == null) {
        if (generation == _generation && ref.mounted) {
          state = RegionBriefState(
            status: previous == null
                ? RegionBriefLoadStatus.degraded
                : RegionBriefLoadStatus.ready,
            brief: previous,
            errorCode: 'location_unavailable',
          );
        }
        return;
      }
      final cacheKey = RegionBriefCacheKey.forPoint(location, locale: 'zh-CN');
      if (previous == null) {
        final cached = await ref.read(regionBriefCacheProvider).read(cacheKey);
        if (cached != null && generation == _generation && ref.mounted) {
          previous = cached;
          state = RegionBriefState(
            status: RegionBriefLoadStatus.refreshing,
            brief: cached,
          );
        }
      }
      final brief = await ref
          .read(regionBriefRepositoryProvider)
          .fetch(
            RegionBriefRequest(
              snapshotId: snapshot.id,
              activationType: manual
                  ? 'user_manual'
                  : 'foreground_opportunistic',
              locale: 'zh-CN',
              center: location,
              radiusMeters: _radiusFor(profile),
              sceneProfile: profile,
              requestedSections: const [
                'identity',
                'orientation',
                'photoThemes',
                'happeningNow',
                'places',
                'localTaste',
                'etiquette',
                'practical',
              ],
            ),
          );
      if (generation != _generation || !ref.mounted) return;
      if (brief.hasUsableFacts) {
        await ref.read(regionBriefCacheProvider).write(cacheKey, brief);
        if (generation != _generation || !ref.mounted) return;
      }
      state = RegionBriefState(
        status:
            brief.status == RegionBriefStatus.pending ||
                brief.status == RegionBriefStatus.unavailable
            ? RegionBriefLoadStatus.degraded
            : RegionBriefLoadStatus.ready,
        brief: brief,
      );
      _scheduleRetryIfNeeded(brief);
    } on RegionBriefFailure catch (error) {
      if (generation != _generation || !ref.mounted) return;
      state = RegionBriefState(
        status: previous == null
            ? RegionBriefLoadStatus.error
            : RegionBriefLoadStatus.degraded,
        brief: previous,
        errorCode: error.code,
      );
    } on Object {
      if (generation != _generation || !ref.mounted) return;
      state = RegionBriefState(
        status: previous == null
            ? RegionBriefLoadStatus.error
            : RegionBriefLoadStatus.degraded,
        brief: previous,
        errorCode: 'unavailable',
      );
    }
  }

  void _scheduleRetryIfNeeded(RegionBrief brief) {
    if ((brief.status != RegionBriefStatus.pending &&
            brief.status != RegionBriefStatus.unavailable) ||
        brief.refresh.retryAfter == null ||
        _automaticRetries >= _maximumAutomaticRetries) {
      return;
    }
    final requested = brief.refresh.retryAfter!;
    final delay = requested < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : requested > const Duration(minutes: 1)
        ? const Duration(minutes: 1)
        : requested;
    _retryTimer = Timer(delay, () {
      if (!ref.mounted) return;
      _automaticRetries += 1;
      unawaited(load());
    });
  }

  static int _radiusFor(ExplorationSceneProfile profile) =>
      switch (profile.mobility) {
        _
            when profile.remoteness == RemotenessLevel.remote ||
                profile.remoteness == RemotenessLevel.extreme =>
          50000,
        _ when profile.mobility.name == 'driving' => 20000,
        _ => 5000,
      };
}

final regionBriefControllerProvider =
    NotifierProvider<RegionBriefController, RegionBriefState>(
      RegionBriefController.new,
    );
