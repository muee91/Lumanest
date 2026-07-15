import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/persistent_context_cache.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/scene_evidence_repository.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/location/fixed_location_repository.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';
import 'package:luma_nest/src/infrastructure/location/geolocator_repository.dart';
import 'package:luma_nest/src/infrastructure/location/amap_location_gateway.dart';
import 'package:luma_nest/src/infrastructure/location/amap_scene_evidence_repository.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';
import 'package:luma_nest/src/infrastructure/solar/nrel_solar_service.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_client.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_repository.dart';
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
  final manual = ref.watch(manualLocationProvider);
  // A base region is an explicit, local fallback. A one-off manual selection
  // still wins for the active session and neither source is sent as a profile.
  final baseRegion = ref.watch(baseRegionProvider).asData?.value;
  final selectedLocation = manual?.location ?? baseRegion?.location;
  return selectedLocation == null
      ? ref.watch(locationRepositoryProvider)
      : FixedLocationRepository(selectedLocation);
});

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  return QWeatherRepository(
    QWeatherClient(
      apiHost: config.qweatherApiHost,
      tokenEndpoint: config.qweatherTokenEndpoint,
      serviceToken: config.lumaNestServiceToken,
      transport: DioQWeatherTransport(dio),
    ),
  );
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

final sceneEvidenceRepositoryProvider = Provider<SceneEvidenceRepository?>((
  ref,
) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return AmapSceneEvidenceRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioSceneEvidenceTransport(
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

final environmentLoaderProvider = Provider<EnvironmentLoader>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return EnvironmentLoader(
    qweatherConfigured: config.isQWeatherConfigured,
    locationRepository: ref.watch(effectiveLocationRepositoryProvider),
    weatherRepository: ref.watch(weatherRepositoryProvider),
    solarService: ref.watch(solarServiceProvider),
    snapshotBuilder: const ContextSnapshotBuilder(),
    cache: ref.watch(contextCacheProvider),
    wildlifeRepository: ref.watch(wildlifeRepositoryProvider),
    sceneEvidenceRepository: ref.watch(sceneEvidenceRepositoryProvider),
    remoteContextRepository: ref.watch(remoteContextRepositoryProvider),
    route: ref.watch(routeContextStateProvider),
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
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      // `environmentLoaderProvider` already watches the effective location
      // source. A refresh is an imperative action: resolve its current value
      // now instead of adding a dependency from this notifier method.
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
