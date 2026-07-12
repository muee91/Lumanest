import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';
import 'package:luma_nest/src/infrastructure/location/geolocator_repository.dart';
import 'package:luma_nest/src/infrastructure/solar/nrel_solar_service.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_client.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_repository.dart';
import 'package:luma_nest/src/infrastructure/wildlife/data_broker_wildlife_repository.dart';

final environmentConfigProvider = Provider<EnvironmentConfig>((ref) {
  return EnvironmentConfig.fromEnvironment();
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return const GeolocatorRepository(GeolocatorGateway());
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
  return InMemoryContextCache();
});

final environmentLoaderProvider = Provider<EnvironmentLoader>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return EnvironmentLoader(
    qweatherConfigured: config.isQWeatherConfigured,
    locationRepository: ref.watch(locationRepositoryProvider),
    weatherRepository: ref.watch(weatherRepositoryProvider),
    solarService: ref.watch(solarServiceProvider),
    snapshotBuilder: const ContextSnapshotBuilder(),
    cache: ref.watch(contextCacheProvider),
    wildlifeRepository: ref.watch(wildlifeRepositoryProvider),
    now: DateTime.now,
    utcOffset: () => DateTime.now().timeZoneOffset,
  );
});

class LiveEnvironmentController extends AsyncNotifier<ContextSnapshot> {
  @override
  Future<ContextSnapshot> build() {
    return ref.watch(environmentLoaderProvider).load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(environmentLoaderProvider).load(),
    );
  }
}

final environmentSnapshotProvider =
    AsyncNotifierProvider<LiveEnvironmentController, ContextSnapshot>(
      LiveEnvironmentController.new,
    );
