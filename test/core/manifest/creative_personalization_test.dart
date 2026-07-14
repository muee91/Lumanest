import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';

void main() {
  test('fingerprint is stable for set order and clamps intensity', () {
    final first = CreativePersonalization(
      photographyPreferences: const {
        PhotographyPreference.city,
        PhotographyPreference.landscape,
      },
      activityPreferences: const {
        ActivityPreference.driving,
        ActivityPreference.lightHiking,
      },
      tone: NarrativeTone.detailed,
      recommendationIntensity: 4,
    );
    final second = CreativePersonalization(
      photographyPreferences: const {
        PhotographyPreference.landscape,
        PhotographyPreference.city,
      },
      activityPreferences: const {
        ActivityPreference.lightHiking,
        ActivityPreference.driving,
      },
      tone: NarrativeTone.detailed,
      recommendationIntensity: 1,
    );

    expect(first.recommendationIntensity, 1);
    expect(first.fingerprint, second.fingerprint);
    expect(first.fingerprint, hasLength(64));
  });

  test('every approved preference maps only to its explicit creative IDs', () {
    final expected = <Object, Set<String>>{
      PhotographyPreference.landscape: {
        'reflection',
        'blue-hour',
        'alpenglow',
        'mist',
        'dust-light',
        'route-light-window',
      },
      PhotographyPreference.humanities: {'humanity-light'},
      PhotographyPreference.astro: {},
      PhotographyPreference.city: {'blue-hour', 'humanity-light'},
      ActivityPreference.driving: {'route-light-window'},
      ActivityPreference.lightHiking: {
        'alpenglow',
        'mist',
        'regional-wildlife',
      },
      ActivityPreference.backpacking: {
        'alpenglow',
        'mist',
        'regional-wildlife',
      },
      ActivityPreference.nicheExploration: {
        'dust-light',
        'humanity-light',
        'regional-wildlife',
      },
    };
    const allKnownIds = {
      'reflection',
      'blue-hour',
      'alpenglow',
      'mist',
      'dust-light',
      'route-light-window',
      'humanity-light',
      'regional-wildlife',
      'unknown-event',
    };

    for (final entry in expected.entries) {
      final personalization = entry.key is PhotographyPreference
          ? CreativePersonalization(
              photographyPreferences: {entry.key as PhotographyPreference},
            )
          : CreativePersonalization(
              activityPreferences: {entry.key as ActivityPreference},
            );
      expect(
        {
          for (final id in allKnownIds)
            if (personalization.matchesCreativeEvent(id)) id,
        },
        entry.value,
        reason: '${entry.key} must use only its approved mapping',
      );
    }
  });

  test('fingerprint changes for each personalization input', () {
    final baseline = CreativePersonalization().fingerprint;

    expect(
      CreativePersonalization(
        photographyPreferences: const {PhotographyPreference.city},
      ).fingerprint,
      isNot(baseline),
    );
    expect(
      CreativePersonalization(
        activityPreferences: const {ActivityPreference.driving},
      ).fingerprint,
      isNot(baseline),
    );
    expect(
      CreativePersonalization(tone: NarrativeTone.concise).fingerprint,
      isNot(baseline),
    );
    expect(
      CreativePersonalization(recommendationIntensity: 0.7).fingerprint,
      isNot(baseline),
    );
  });
}
