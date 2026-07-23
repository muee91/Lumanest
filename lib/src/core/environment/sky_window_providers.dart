import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_sky_window_repository.dart';

class SkyWindowRequest {
  const SkyWindowRequest({
    required this.point,
    required this.startAt,
    this.hours = 72,
    this.locale = 'zh-CN',
  });

  final GeoPoint point;
  final DateTime startAt;
  final int hours;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is SkyWindowRequest &&
      other.point.latitude == point.latitude &&
      other.point.longitude == point.longitude &&
      other.point.coordinateSystem == point.coordinateSystem &&
      other.startAt.toUtc() == startAt.toUtc() &&
      other.hours == hours &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(
        point.latitude,
        point.longitude,
        point.coordinateSystem,
        startAt.toUtc(),
        hours,
        locale,
      );
}

final skyWindowRepositoryProvider =
    Provider<DataBrokerSkyWindowRepository?>((ref) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerSkyWindowRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioSiteEnvironmentTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 4),
        ),
      ),
    ),
  );
});

final skyWindowForecastProvider = FutureProvider.autoDispose
    .family<SkyWindowForecast?, SkyWindowRequest>((ref, request) async {
  final repository = ref.watch(skyWindowRepositoryProvider);
  if (repository == null) return null;
  try {
    return await repository.fetch(
      request.point,
      startAt: request.startAt,
      hours: request.hours,
      locale: request.locale,
    );
  } on Object {
    // Sky-window forecasts are supplementary and must never replace the current
    // Context snapshot, safety state, or Explore content when a source degrades.
    return null;
  }
});
