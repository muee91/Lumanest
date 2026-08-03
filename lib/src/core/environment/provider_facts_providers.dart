import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/core/environment/provider_facts_repository.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_provider_facts_repository.dart';

final providerFactsRepositoryProvider = Provider<ProviderFactsRepository?>((
  ref,
) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerProviderFactsRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioProviderFactsTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 4),
        ),
      ),
    ),
  );
});

final providerFactsProvider = FutureProvider<ProviderFactsBundle?>((ref) async {
  final snapshot = await ref.watch(environmentSnapshotProvider.future);
  final repository = ref.watch(providerFactsRepositoryProvider);
  final location = snapshot.location;
  if (repository == null || location == null) return null;
  try {
    return await repository.fetch(location);
  } on Object {
    // Every upstream is supplementary. Failure must not block Explore or
    // silently replace the authoritative Context snapshot.
    return null;
  }
});
