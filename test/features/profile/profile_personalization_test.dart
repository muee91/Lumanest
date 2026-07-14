import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/features/profile/application/profile_personalization.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

void main() {
  test('maps every persisted profile option to the typed contract', () {
    final personalization = ProfilePersonalization.fromPreferences(
      const ProfilePreferences(
        photographyPreferences: {'风光', '人文', '星空', '城市'},
        activityPreferences: {'自驾', '轻徒步', '重装徒步', '小众探索'},
        aiTone: AiTone.detailed,
        recommendationIntensity: 0.8,
      ),
    );

    expect(personalization.photographyPreferences, {
      PhotographyPreference.landscape,
      PhotographyPreference.humanities,
      PhotographyPreference.astro,
      PhotographyPreference.city,
    });
    expect(personalization.activityPreferences, {
      ActivityPreference.driving,
      ActivityPreference.lightHiking,
      ActivityPreference.backpacking,
      ActivityPreference.nicheExploration,
    });
    expect(personalization.tone, NarrativeTone.detailed);
    expect(personalization.recommendationIntensity, 0.8);
  });

  test(
    'unknown labels are ignored rather than becoming inferred interests',
    () {
      final personalization = ProfilePersonalization.fromPreferences(
        const ProfilePreferences(
          photographyPreferences: {'未知摄影类型'},
          activityPreferences: {'未知活动'},
        ),
      );

      expect(personalization.photographyPreferences, isEmpty);
      expect(personalization.activityPreferences, isEmpty);
    },
  );

  test(
    'equipment and accessibility never change the preference fingerprint',
    () {
      final first = ProfilePersonalization.fromPreferences(
        const ProfilePreferences(
          photographyPreferences: {'人文'},
          activityPreferences: {'小众探索'},
          aiTone: AiTone.concise,
          recommendationIntensity: 0.7,
          equipmentList: '相机、35mm、三脚架',
          reduceMotion: true,
          highContrast: true,
        ),
      );
      final second = ProfilePersonalization.fromPreferences(
        const ProfilePreferences(
          photographyPreferences: {'人文'},
          activityPreferences: {'小众探索'},
          aiTone: AiTone.concise,
          recommendationIntensity: 0.7,
          equipmentList: '手机',
          reduceFlashing: true,
          ambientBackgroundEnabled: false,
        ),
      );

      expect(first.fingerprint, second.fingerprint);
    },
  );
}
