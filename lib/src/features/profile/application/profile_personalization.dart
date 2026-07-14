import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

/// Converts local persisted profile values into the bounded core contract.
abstract final class ProfilePersonalization {
  static CreativePersonalization fromPreferences(
    ProfilePreferences preferences,
  ) {
    return CreativePersonalization(
      photographyPreferences: preferences.photographyPreferences
          .map(_photographyPreference)
          .whereType<PhotographyPreference>()
          .toSet(),
      activityPreferences: preferences.activityPreferences
          .map(_activityPreference)
          .whereType<ActivityPreference>()
          .toSet(),
      tone: switch (preferences.aiTone) {
        AiTone.concise => NarrativeTone.concise,
        AiTone.balanced => NarrativeTone.balanced,
        AiTone.detailed => NarrativeTone.detailed,
      },
      recommendationIntensity: preferences.recommendationIntensity,
    );
  }

  static PhotographyPreference? _photographyPreference(String value) =>
      switch (value) {
        '风光' => PhotographyPreference.landscape,
        '人文' => PhotographyPreference.humanities,
        '星空' => PhotographyPreference.astro,
        '城市' => PhotographyPreference.city,
        _ => null,
      };

  static ActivityPreference? _activityPreference(String value) =>
      switch (value) {
        '自驾' => ActivityPreference.driving,
        '轻徒步' => ActivityPreference.lightHiking,
        '重装徒步' => ActivityPreference.backpacking,
        '小众探索' => ActivityPreference.nicheExploration,
        _ => null,
      };
}
