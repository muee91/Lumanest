import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/explore/application/exploration_scene_profile_resolver.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_request_policy.dart';
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
    this.verification = false,
    this.lastExpandedAt,
    this.lastVerifiedAt,
  });

  const RegionBriefState.idle() : this(status: RegionBriefLoadStatus.idle);

  final RegionBriefLoadStatus status;
  final RegionBrief? brief;
  final String? errorCode;
  final bool manualExpansion;
  final bool verification;
  final DateTime? lastExpandedAt;
  final DateTime? lastVerifiedAt;

  bool get hasUsableBrief => brief?.hasUsableFacts == true;

  bool get isBusy =>
      status == RegionBriefLoadStatus.loading ||
      status == RegionBriefLoadStatus.refreshing;

  bool get isExpanding => manualExpansion && isBusy;

  bool get isVerifying => verification && isBusy;
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
    // Notifier state is not readable until build returns. Defer the automatic
    // load so its stale-while-refresh transition starts after initialization.
    Future.microtask(load);
    return const RegionBriefState.idle();
  }

  Future<void> load({bool manual = false, bool verification = false}) async {
    _retryTimer?.cancel();
    if (manual || verification) _automaticRetries = 0;
    var previous = state.brief;
    if (verification && !RegionBriefRequestPolicy.needsVerification(previous)) {
      return;
    }
    final generation = ++_generation;
    final previousExpandedAt = state.lastExpandedAt;
    final previousVerifiedAt = state.lastVerifiedAt;
    state = RegionBriefState(
      status: previous == null
          ? RegionBriefLoadStatus.loading
          : RegionBriefLoadStatus.refreshing,
      brief: previous,
      manualExpansion: manual,
      verification: verification,
      lastExpandedAt: previousExpandedAt,
      lastVerifiedAt: previousVerifiedAt,
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
            lastVerifiedAt: previousVerifiedAt,
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
            verification: verification,
            lastExpandedAt: previousExpandedAt,
            lastVerifiedAt: previousVerifiedAt,
          );
        }
      }
      final plan = verification
          ? RegionBriefRequestPolicy.verificationPlan(profile, previous!)
          : RegionBriefRequestPolicy.plan(profile, manual: manual);
      final incoming = await ref
          .read(regionBriefRepositoryProvider)
          .fetch(
            RegionBriefRequest(
              snapshotId: snapshot.id,
              activationType: plan.activationType,
              locale: 'zh-CN',
              center: location,
              radiusMeters: plan.radiusMeters,
              sceneProfile: profile,
              requestedSections: plan.requestedSections,
            ),
          );
      if (generation != _generation || !ref.mounted) return;
      final keepPrevious = RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: previous,
        incoming: incoming,
        manual: manual,
        verification: verification,
      );
      final accepted = keepPrevious ? previous! : incoming;
      if (!keepPrevious && incoming.hasUsableFacts) {
        await ref.read(regionBriefCacheProvider).write(cacheKey, incoming);
        if (generation != _generation || !ref.mounted) return;
      }
      state = RegionBriefState(
        status:
            incoming.status == RegionBriefStatus.pending ||
                incoming.status == RegionBriefStatus.unavailable
            ? RegionBriefLoadStatus.degraded
            : RegionBriefLoadStatus.ready,
        brief: accepted,
        lastExpandedAt: manual && !keepPrevious && incoming.hasUsableFacts
            ? DateTime.now().toUtc()
            : previousExpandedAt,
        lastVerifiedAt:
            verification && !keepPrevious && incoming.hasUsableFacts
            ? DateTime.now().toUtc()
            : previousVerifiedAt,
      );
      _scheduleRetryIfNeeded(
        incoming,
        manual: manual,
        verification: verification,
      );
    } on RegionBriefFailure catch (error) {
      if (generation != _generation || !ref.mounted) return;
      state = RegionBriefState(
        status: previous == null
            ? RegionBriefLoadStatus.error
            : RegionBriefLoadStatus.degraded,
        brief: previous,
        errorCode: error.code,
        lastExpandedAt: previousExpandedAt,
        lastVerifiedAt: previousVerifiedAt,
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
        lastVerifiedAt: previousVerifiedAt,
      );
    }
  }

  void _scheduleRetryIfNeeded(
    RegionBrief brief, {
    required bool manual,
    required bool verification,
  }) {
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
      unawaited(load(manual: manual, verification: verification));
    });
  }
}

final regionBriefControllerProvider =
    NotifierProvider<RegionBriefController, RegionBriefState>(
      RegionBriefController.new,
    );
