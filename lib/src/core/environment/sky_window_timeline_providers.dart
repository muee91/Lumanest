import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/sky_window_providers.dart';
import 'package:luma_nest/src/core/environment/sky_window_timeline.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_sky_window_timeline_repository.dart';

final skyWindowTimelineRepositoryProvider =
    Provider<DataBrokerSkyWindowTimelineRepository?>((ref) {
      final config = ref.watch(environmentConfigProvider);
      if (!config.isDataBrokerConfigured) return null;
      return DataBrokerSkyWindowTimelineRepository(
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

final skyWindowTimelineProvider = FutureProvider.autoDispose
    .family<SkyWindowTimelineForecast?, SkyWindowRequest>((ref, request) async {
      final repository = ref.watch(skyWindowTimelineRepositoryProvider);
      if (repository == null) return null;
      try {
        return await repository.fetch(
          request.point,
          startAt: request.startAt,
          hours: request.hours,
          locale: request.locale,
        );
      } on Object {
        // Timeline data is supplementary. Failure must not alter Context,
        // safety, Today opportunities, or the existing sky-window fallback.
        return null;
      }
    });
