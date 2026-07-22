import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/core/environment/site_environment_repository.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';

final siteEnvironmentRepositoryProvider = Provider<SiteEnvironmentRepository?>((ref) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerSiteEnvironmentRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioSiteEnvironmentTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 3),
        ),
      ),
    ),
  );
});

final siteEnvironmentFactsProvider = FutureProvider<SiteEnvironmentFacts?>((ref) async {
  final snapshot = await ref.watch(environmentSnapshotProvider.future);
  final location = snapshot.location;
  final repository = ref.watch(siteEnvironmentRepositoryProvider);
  if (location == null || repository == null) return null;
  try {
    return await repository.fetch(location);
  } on Object {
    // Elevation and night-sky background are supplementary facts. Their failure
    // must never replace the current Context snapshot or block Explore.
    return null;
  }
});
