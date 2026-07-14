import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/profile/application/profile_personalization.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';

final creativePersonalizationProvider = Provider<CreativePersonalization>((
  ref,
) {
  return ProfilePersonalization.fromPreferences(
    ref.watch(profilePreferencesProvider),
  );
});

/// The one personalized manifest consumed by Today, Inspiration, and AI copy.
final personalizedManifestProvider =
    Provider.family<UiManifest, ContextSnapshot>((ref, snapshot) {
      return ManifestPolicy.build(
        snapshot,
        personalization: ref.watch(creativePersonalizationProvider),
      );
    });
