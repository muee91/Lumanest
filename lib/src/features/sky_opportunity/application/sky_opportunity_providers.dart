import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_api.dart';
import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_repository.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

typedef SkyOpportunityCoordinate = ({
  double latitude,
  double longitude,
  SkyOpportunityDailyFocus focus,
});

SkyOpportunityDailyFocus skyOpportunityFocusForSnapshot(
  ContextSnapshot snapshot,
  DateTime now,
) {
  final sunrise = snapshot.sunrise;
  return sunrise != null && sunrise.isAfter(now)
      ? SkyOpportunityDailyFocus.preSunrise
      : SkyOpportunityDailyFocus.next;
}

final skyOpportunityRepositoryProvider = Provider<SkyOpportunityRepository>((
  ref,
) {
  final config = ref.watch(environmentConfigProvider);
  return DataBrokerSkyOpportunityRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioSkyOpportunityTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 13),
          sendTimeout: const Duration(seconds: 5),
        ),
      ),
    ),
  );
});

final dailySkyOpportunitiesProvider = FutureProvider.autoDispose
    .family<DailySkyOpportunities, SkyOpportunityCoordinate>((ref, coordinate) {
      return ref
          .watch(skyOpportunityRepositoryProvider)
          .fetchDaily(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            focus: coordinate.focus,
          );
    });
