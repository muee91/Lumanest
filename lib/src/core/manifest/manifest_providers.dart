import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/local_creative_affinity.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/features/profile/application/profile_personalization.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';

final creativePersonalizationProvider = Provider<CreativePersonalization>((
  ref,
) {
  final base = ProfilePersonalization.fromPreferences(
    ref.watch(profilePreferencesProvider),
  );
  final results =
      ref.watch(userLibraryProvider).asData?.value.opportunityResults ??
      const [];
  return CreativePersonalization(
    photographyPreferences: base.photographyPreferences,
    activityPreferences: base.activityPreferences,
    tone: base.tone,
    recommendationIntensity: base.recommendationIntensity,
    localAffinity: LocalCreativeAffinity.fromResults(results),
  );
});

/// The one personalized manifest consumed by Today, Inspiration, and AI copy.
final personalizedManifestProvider =
    Provider.family<UiManifest, ContextSnapshot>((ref, snapshot) {
      final manifest = ManifestPolicy.build(
        snapshot,
        personalization: ref.watch(creativePersonalizationProvider),
      );
      ref
          .read(appLoggerProvider)
          .debug(
            LogCategory.manifest,
            'manifest.built',
            data: {
              LogDataKey.scene: snapshot.primaryScene.name,
              LogDataKey.eventCount: manifest.creativeItems.length,
              LogDataKey.safetyCount: manifest.safety.length,
            },
          );
      return manifest;
    });
