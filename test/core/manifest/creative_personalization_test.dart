import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';

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
        'session.water.morning',
        'session.water.evening',
        'session.mountain.morning',
        'session.mountain.evening',
        'session.desert.side_light',
        'event.sky.sunset_glow',
        'event.atmosphere.morning_mist',
        'session.route.light_window',
      },
      PhotographyPreference.humanities: {'session.city.after_rain'},
      PhotographyPreference.astro: {
        'event.astro.moon_window',
        'event.astro.meteor_shower',
        'event.astro.special_authority',
      },
      PhotographyPreference.city: {
        'session.city.blue_hour',
        'session.city.after_rain',
        'event.sky.sunset_glow',
        'session.route.light_window',
      },
      ActivityPreference.driving: {'session.route.light_window'},
      ActivityPreference.lightHiking: {
        'session.mountain.morning',
        'session.mountain.evening',
        'session.desert.side_light',
        'event.sky.sunset_glow',
        'event.atmosphere.morning_mist',
        'session.route.light_window',
        'regional-wildlife',
      },
      ActivityPreference.backpacking: {
        'session.mountain.morning',
        'session.mountain.evening',
        'session.desert.side_light',
        'event.sky.sunset_glow',
        'event.atmosphere.morning_mist',
        'session.route.light_window',
        'regional-wildlife',
      },
      ActivityPreference.nicheExploration: {
        'session.desert.side_light',
        'session.route.light_window',
        'regional-wildlife',
      },
    };
    final allKnownIds = {
      ...OpportunityCatalog.current.definitions
          .where((item) => item.isActiveCore)
          .map((item) => item.id),
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
