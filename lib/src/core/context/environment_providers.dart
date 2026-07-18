import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/persistent_context_cache.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/context/safety_detail.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/location/fixed_location_repository.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';
import 'package:luma_nest/src/infrastructure/location/geolocator_repository.dart';
import 'package:luma_nest/src/infrastructure/location/amap_location_gateway.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';
import 'package:luma_nest/src/core/context/debug_simulation_session.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_safety_detail_repository.dart';
import 'package:luma_nest/src/infrastructure/solar/nrel_solar_service.dart';
import 'package:luma_nest/src/infrastructure/wildlife/data_broker_wildlife_repository.dart';
import 'package:luma_nest/src/features/location/application/manual_location_providers.dart';
import 'package:luma_nest/src/features/location/application/base_region_controller.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/amap_location_search_repository.dart';
import 'package:luma_nest/src/features/location/infrastructure/location_search_cache.dart';
import 'package:luma_nest/src/features/location/infrastructure/resilient_location_search_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final environmentConfigProvider = Provider<EnvironmentConfig>((ref) {
  return EnvironmentConfig.fromEnvironment();
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return GeolocatorRepository(
    const GeolocatorGateway(),
    // AMap native location is Android's primary automatic location source.
    // System location remains the fallback when AMap is absent or unavailable.
    // The SDK key is configured at build time and never sent to the NAS broker.
    amapGateway: config.isAmapConfigured
        ? MethodChannelAmapLocationGateway(androidApiKey: config.amapAndroidKey)
        : null,
  );
});

final effectiveLocationRepositoryProvider = Provider<LocationRepository>((ref) {
  final manual = ref.watch(manualLocationProvider).asData?.value;
  // A base region is an explicit, local fallback. A one-off manual selection
  // still wins for the active session and neither source is sent as a profile.
  final baseRegion = ref.watch(baseRegionProvider).asData?.value;
  final selectedLocation = manual?.location ?? baseRegion?.location;
  return selectedLocation == null
      ? ref.watch(locationRepositoryProvider)
      : FixedLocationRepository(selectedLocation);
});

final solarServiceProvider = Provider<SolarService>((ref) {
  return NrelSolarService();
});

final locationSearchCacheProvider = Provider<LocationSearchCache>((ref) {
  return PersistentLocationSearchCache(SharedPreferencesAsync());
});

final locationSearchRepositoryProvider = Provider<LocationSearchRepository>((
  ref,
) {
  final config = ref.watch(environmentConfigProvider);
  final primary = AmapLocationSearchRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioLocationSearchTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      ),
    ),
  );
  return ResilientLocationSearchRepository(
    primary: primary,
    cache: ref.watch(locationSearchCacheProvider),
  );
});

final wildlifeRepositoryProvider = Provider<WildlifeRepository?>((ref) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
    ),
  );
  return DataBrokerWildlifeRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioWildlifeDataTransport(dio),
  );
});

final contextCacheProvider = Provider<ContextCache>((ref) {
  return PersistentContextCache(SharedPreferencesAsync());
});

final contextCacheWriteGuardProvider = Provider<ContextCacheWriteGuard>((ref) {
  return ContextCacheWriteGuard();
});

final remoteContextRepositoryProvider = Provider<RemoteContextRepository?>((
  ref,
) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerContextRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    debugSimulationSession: DebugSimulationSession.headerValue,
    transport: DioContextDataTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      ),
    ),
  );
});

final shootingTargetSessionRepositoryProvider =
    Provider<ShootingTargetSessionRepository?>((ref) {
      final repository = ref.watch(remoteContextRepositoryProvider);
      return switch (repository) {
        ShootingTargetSessionRepository value => value,
        _ => null,
      };
    });

final shootingFeedbackRepositoryProvider =
    Provider<ShootingFeedbackRepository?>((ref) {
      final repository = ref.watch(remoteContextRepositoryProvider);
      return switch (repository) {
        ShootingFeedbackRepository value => value,
        _ => null,
      };
    });

final safetyDetailRepositoryProvider = Provider<SafetyDetailRepository?>((ref) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerSafetyDetailRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioSafetyDetailTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      ),
    ),
  );
});

final environmentLoaderProvider = Provider<EnvironmentLoader>((ref) {
  return EnvironmentLoader(
    locationRepository: ref.watch(effectiveLocationRepositoryProvider),
    solarService: ref.watch(solarServiceProvider),
    cache: ref.watch(contextCacheProvider),
    wildlifeRepository: ref.watch(wildlifeRepositoryProvider),
    remoteContextRepository: ref.watch(remoteContextRepositoryProvider),
    route: ref.watch(routeContextStateProvider),
    corridor: ref.watch(routeCorridorContextProvider),
    logger: ref.watch(appLoggerProvider),
    cacheWriteGuard: ref.watch(contextCacheWriteGuardProvider),
    now: DateTime.now,
    utcOffset: () => DateTime.now().timeZoneOffset,
  );
});

class LiveEnvironmentController extends AsyncNotifier<ContextSnapshot> {
  @override
  Future<ContextSnapshot> build() async {
    final loader = ref.watch(environmentLoaderProvider);
    final cached = await loader.cache.readLatest();
    if (cached == null) return _load(loader, trigger: 'automatic');

    final cacheIsCurrent =
        !cached.isStale &&
        cached.expiresAt.toUtc().isAfter(loader.now().toUtc());
    final startupSnapshot = cacheIsCurrent ? cached : cached.asStale();
    final logger = ref.read(appLoggerProvider);
    final logData = {
      LogDataKey.freshness: startupSnapshot.dataFreshness.name,
      LogDataKey.scene: startupSnapshot.primaryScene.name,
    };
    if (startupSnapshot.isStale) {
      logger.warning(
        LogCategory.contextCache,
        'context.cache_restored',
        data: logData,
      );
    } else {
      logger.debug(
        LogCategory.contextCache,
        'context.cache_restored',
        data: logData,
      );
    }
    // Schedule the refresh after the cached build value has committed so a
    // fast network response cannot be overwritten by the startup cache.
    unawaited(Future<void>(() => _refreshInBackground(loader)));
    return startupSnapshot;
  }

  Future<void> _refreshInBackground(EnvironmentLoader loader) async {
    try {
      final snapshot = await _load(loader, trigger: 'background');
      if (ref.mounted) state = AsyncData(snapshot);
    } on Object {
      // The cached snapshot remains the safe visible state. `_load` already
      // records a sanitized failure category without exposing raw errors.
    }
  }

  Future<void> refresh() async {
    // A manual refresh is a content update, not a navigation state change.
    // Keep the last safe snapshot visible while RefreshIndicator describes the
    // in-flight request; replacing it with AsyncLoading makes the whole Today
    // page flash to a spinner and hides safety guidance unnecessarily.
    final previous = state.asData?.value;
    if (previous != null) {
      try {
        state = AsyncData(
          await _load(ref.read(environmentLoaderProvider), trigger: 'manual'),
        );
      } on Object {
        // `_load` records a sanitized category. The existing snapshot remains
        // the truthful, usable fallback until a later refresh succeeds.
      }
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _load(ref.read(environmentLoaderProvider), trigger: 'manual'),
    );
  }

  Future<ContextSnapshot> _load(
    EnvironmentLoader loader, {
    required String trigger,
  }) async {
    final logger = ref.read(appLoggerProvider);
    logger.debug(
      LogCategory.contextSnapshot,
      'context.refresh_started',
      data: {LogDataKey.source: trigger},
    );
    try {
      final snapshot = await loader.load();
      final data = {
        LogDataKey.freshness: snapshot.dataFreshness.name,
        LogDataKey.scene: snapshot.primaryScene.name,
      };
      if (snapshot.isStale) {
        logger.warning(
          LogCategory.degradation,
          'context.stale_fallback',
          data: data,
        );
      } else {
        logger.info(
          LogCategory.contextSnapshot,
          'context.refresh_completed',
          data: data,
        );
      }
      return snapshot;
    } on EnvironmentLoadFailure catch (failure) {
      logger.warning(
        LogCategory.degradation,
        'context.refresh_failed',
        data: {LogDataKey.reason: failure.kind.name},
      );
      rethrow;
    } on Object {
      logger.error(LogCategory.error, 'context.unexpected_failure');
      rethrow;
    }
  }
}

final environmentSnapshotProvider =
    AsyncNotifierProvider<LiveEnvironmentController, ContextSnapshot>(
      LiveEnvironmentController.new,
      // Environment failures need an explicit, understandable recovery UI.
      // Retrying automatically would replace that state with an endless
      // spinner when the device has no GPS fix or network connection.
      retry: (_, _) => null,
    );
