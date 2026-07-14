import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

enum PhotographyPreference { landscape, humanities, astro, city }

enum ActivityPreference { driving, lightHiking, backpacking, nicheExploration }

enum NarrativeTone { concise, balanced, detailed }

/// Local-only inputs that may reorder already-established creative events.
///
/// This type intentionally has no equipment, device, accessibility, location,
/// or identity fields. Those values therefore cannot enter recommendation
/// ranking, the preference fingerprint, or a narrative request by accident.
class CreativePersonalization {
  CreativePersonalization({
    Set<PhotographyPreference> photographyPreferences = const {},
    Set<ActivityPreference> activityPreferences = const {},
    this.tone = NarrativeTone.balanced,
    double recommendationIntensity = 0.5,
  }) : photographyPreferences = UnmodifiableSetView(
         Set.of(photographyPreferences),
       ),
       activityPreferences = UnmodifiableSetView(Set.of(activityPreferences)),
       recommendationIntensity = recommendationIntensity
           .clamp(0.0, 1.0)
           .toDouble();

  static final neutral = CreativePersonalization();

  final Set<PhotographyPreference> photographyPreferences;
  final Set<ActivityPreference> activityPreferences;
  final NarrativeTone tone;
  final double recommendationIntensity;

  bool get hasRecommendationPreferences =>
      photographyPreferences.isNotEmpty || activityPreferences.isNotEmpty;

  late final String fingerprint = sha256
      .convert(utf8.encode(_canonicalFingerprintInput()))
      .toString();

  bool matchesCreativeEvent(String eventId) {
    for (final preference in photographyPreferences) {
      if (_photographyEvents[preference]!.contains(eventId)) return true;
    }
    for (final preference in activityPreferences) {
      if (_activityEvents[preference]!.contains(eventId)) return true;
    }
    return false;
  }

  String _canonicalFingerprintInput() {
    final photography =
        photographyPreferences.map((value) => value.name).toList()..sort();
    final activities = activityPreferences.map((value) => value.name).toList()
      ..sort();
    return 'photography=${photography.join(',')};'
        'activity=${activities.join(',')};'
        'tone=${tone.name};'
        'intensity=${recommendationIntensity.toStringAsFixed(1)}';
  }
}

const _photographyEvents = <PhotographyPreference, Set<String>>{
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
};

const _activityEvents = <ActivityPreference, Set<String>>{
  ActivityPreference.driving: {'route-light-window'},
  ActivityPreference.lightHiking: {'alpenglow', 'mist', 'regional-wildlife'},
  ActivityPreference.backpacking: {'alpenglow', 'mist', 'regional-wildlife'},
  ActivityPreference.nicheExploration: {
    'dust-light',
    'humanity-light',
    'regional-wildlife',
  },
};
