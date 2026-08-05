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
  const RegionBriefState({
    required this.status,
    this.brief,
    this.errorCode,
    this.manualExpansion = false,
    this.lastExpandedAt,
  });

  const RegionBriefState.idle() : this(status: RegionBriefLoadStatus.idle);

  final RegionBriefLoadStatus status;
  final RegionBrief? brief;
  final String? errorCode;
  final bool manualExpansion;
  final DateTime? lastExpandedAt;

  bool get hasUsableBrief => brief?.hasUsableFacts == true;

  bool get isExpanding =>
      manualExpansion &&
      (status == RegionBriefLoadStatus.loading ||
          status == RegionBriefLoadStatus.refreshing);
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
  static const _automaticSections = <String>[
    'identity',
    'orientation',
    'photoThemes',
    'practical',
  ];
  static const _expandedSections = <String>[
    'identity',
    'orientation',
    'photoThemes',
    'happeningNow',
    'places',
    'localTaste',
    'etiquette',
    'practical',
  ];

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
    // Notifier state is not readable until build returns. Defer the automatic
    // load so its stale-while-refresh transition starts after initialization.
    Future.microtask(load);
    return const RegionBriefState.idle();
  }

  Future<void> load({bool manual = false}) async {
    _retryTimer?.cancel();
    if (manual) _automaticRetries = 0;
    final generation = ++_generation;
    var previous = state.brief;
    final previousExpandedAt = state.lastExpandedAt;
    state = RegionBriefState(
      status: previous == null
          ? RegionBriefLoadStatus.loading
          : RegionBriefLoadStatus.refreshing,
      brief: previous,
      manualExpansion: manual,
      lastExpandedAt: previousExpandedAt,
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
            lastExpandedAt: previousExpandedAt,
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
            manualExpansion: manual,
            lastExpandedAt: previousExpandedAt,
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
              radiusMeters: _radiusFor(profile, expanded: manual),
              sceneProfile: profile,
              requestedSections: manual
                  ? _expandedSections
                  : _automaticSections,
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
        lastExpandedAt: manual && brief.hasUsableFacts
            ? DateTime.now().toUtc()
            : previousExpandedAt,
      );
      _scheduleRetryIfNeeded(brief, manual: manual);
    } on RegionBriefFailure catch (error) {
      if (generation != _generation || !ref.mounted) return;
      state = RegionBriefState(
        status: previous == null
            ? RegionBriefLoadStatus.error
            : RegionBriefLoadStatus.degraded,
        brief: previous,
        errorCode: error.code,
        lastExpandedAt: previousExpandedAt,
      );
    } on Object {
      if (generation != _generation || !ref.mounted) return;
      state = RegionBriefState(
        status: previous == null
            ? RegionBriefLoadStatus.error
            : RegionBriefLoadStatus.degraded,
        brief: previous,
        errorCode: 'unavailable',
        lastExpandedAt: previousExpandedAt,
      );
    }
  }

  void _scheduleRetryIfNeeded(RegionBrief brief, {required bool manual}) {
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
      unawaited(load(manual: manual));
    });
  }

  static int _radiusFor(
    ExplorationSceneProfile profile, {
    required bool expanded,
  }) {
    if (profile.remoteness == RemotenessLevel.remote ||
        profile.remoteness == RemotenessLevel.extreme) {
      return 50000;
    }
    if (profile.mobility.name == 'driving') {
      return expanded ? 35000 : 20000;
    }
    if (!expanded) return 5000;
    return switch (profile.settlement) {
      SettlementType.historicTown ||
      SettlementType.historicDistrict ||
      SettlementType.village => 15000,
      SettlementType.scenicArea => 20000,
      _ => 12000,
    };
  }
}

final regionBriefControllerProvider =
    NotifierProvider<RegionBriefController, RegionBriefState>(
      RegionBriefController.new,
    );
