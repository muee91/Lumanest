import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';

enum PhotographyPreference { landscape, humanities, astro, city, ecology }

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
    Map<String, double> localAffinity = const {},
  }) : photographyPreferences = UnmodifiableSetView(
         Set.of(photographyPreferences),
       ),
       activityPreferences = UnmodifiableSetView(Set.of(activityPreferences)),
       recommendationIntensity = recommendationIntensity
           .clamp(0.0, 1.0)
           .toDouble(),
       localAffinity = UnmodifiableMapView(Map.from(localAffinity));

  static final neutral = CreativePersonalization();

  final Set<PhotographyPreference> photographyPreferences;
  final Set<ActivityPreference> activityPreferences;
  final NarrativeTone tone;
  final double recommendationIntensity;
  final Map<String, double> localAffinity;

  bool get hasRecommendationPreferences =>
      photographyPreferences.isNotEmpty ||
      activityPreferences.isNotEmpty ||
      localAffinity.values.any((value) => value > 0);

  late final String fingerprint = sha256
      .convert(utf8.encode(_canonicalFingerprintInput()))
      .toString();

  bool matchesCreativeEvent(String eventId) {
    if (eventId == 'regional-wildlife') {
      return photographyPreferences.contains(PhotographyPreference.ecology) ||
          activityPreferences.any(
            (value) => value != ActivityPreference.driving,
          );
    }
    final definition = OpportunityCatalog.current.byId[eventId];
    if (definition == null || !definition.isActiveCore) return false;
    final affinities = definition.preferenceAffinities;
    return photographyPreferences.any(
          (value) =>
              affinities.intersection(_photographyAffinities(value)).isNotEmpty,
        ) ||
        activityPreferences.any((value) => _matchesActivity(value, definition));
  }

  double affinityForCreativeEvent(String eventId) =>
      localAffinity[eventId] ?? 0;

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

Set<PhotographyPreferenceId> _photographyAffinities(
  PhotographyPreference preference,
) => switch (preference) {
  PhotographyPreference.landscape => const {
    PhotographyPreferenceId.mountainLandform,
    PhotographyPreferenceId.waterCoast,
    PhotographyPreferenceId.forestDetail,
    PhotographyPreferenceId.aerialSpatial,
  },
  PhotographyPreference.humanities => const {
    PhotographyPreferenceId.humanityStreet,
  },
  PhotographyPreference.astro => const {PhotographyPreferenceId.astroCelestial},
  PhotographyPreference.city => const {
    PhotographyPreferenceId.cityArchitecture,
  },
  PhotographyPreference.ecology => const {
    PhotographyPreferenceId.wildlifeEcology,
  },
};

bool _matchesActivity(
  ActivityPreference activity,
  OpportunityDefinition definition,
) => switch (activity) {
  ActivityPreference.driving => definition.id == 'session.route.light_window',
  ActivityPreference.lightHiking ||
  ActivityPreference.backpacking => definition.preferenceAffinities.any(
    const {
      PhotographyPreferenceId.mountainLandform,
      PhotographyPreferenceId.forestDetail,
      PhotographyPreferenceId.wildlifeEcology,
    }.contains,
  ),
  ActivityPreference.nicheExploration =>
    definition.family == OpportunityFamily.landform ||
        definition.family == OpportunityFamily.ecology ||
        definition.family == OpportunityFamily.humanityRoute,
};
