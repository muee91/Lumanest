import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/narrative/data_broker_manifest_narrative_model.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_coordinator.dart';

final manifestNarrativeModelProvider = Provider<ManifestNarrativeModel?>((ref) {
  final EnvironmentConfig config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerManifestNarrativeModel(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioNarrativeTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      ),
    ),
  );
});

final manifestNarrativeCoordinatorProvider =
    Provider<ManifestNarrativeCoordinator>((ref) {
      return ManifestNarrativeCoordinator(
        model: ref.watch(manifestNarrativeModelProvider),
        // Shares the injected clock with the manifest and the composition, so
        // cache expiry and backoff follow the same instant the UI shows.
        now: ref.watch(currentTimeProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });

// `ContextSnapshot` has no value equality, so each refresh is a new family key.
// autoDispose releases the old key together with its in-flight LLM result.
final manifestNarrativeProvider =
    FutureProvider.autoDispose.family<ManifestNarrative, ContextSnapshot>((
      ref,
      snapshot,
    ) {
      final manifest = ref.watch(personalizedManifestProvider(snapshot));
      final personalization = ref.watch(creativePersonalizationProvider);
      return ref
          .watch(manifestNarrativeCoordinatorProvider)
          .resolve(
            snapshot: snapshot,
            manifest: manifest,
            tone: personalization.tone,
            preferenceFingerprint: personalization.fingerprint,
          );
    });
