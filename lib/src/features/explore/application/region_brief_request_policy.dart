import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

class RegionBriefRequestPlan {
  const RegionBriefRequestPlan({
    required this.activationType,
    required this.radiusMeters,
    required this.requestedSections,
    required this.expanded,
  });

  final String activationType;
  final int radiusMeters;
  final List<String> requestedSections;
  final bool expanded;
}

abstract final class RegionBriefRequestPolicy {
  static const automaticSections = <String>[
    'identity',
    'orientation',
    'photoThemes',
    'practical',
  ];

  static const expandedSections = <String>[
    'identity',
    'orientation',
    'photoThemes',
    'happeningNow',
    'places',
    'localTaste',
    'etiquette',
    'practical',
  ];

  static RegionBriefRequestPlan plan(
    ExplorationSceneProfile profile, {
    required bool manual,
  }) => RegionBriefRequestPlan(
    activationType: manual ? 'user_manual' : 'foreground_opportunistic',
    radiusMeters: radiusFor(profile, expanded: manual),
    requestedSections: manual ? expandedSections : automaticSections,
    expanded: manual,
  );

  static int radiusFor(
    ExplorationSceneProfile profile, {
    required bool expanded,
  }) {
    if (profile.remoteness == RemotenessLevel.remote ||
        profile.remoteness == RemotenessLevel.extreme) {
      return 50000;
    }
    if (profile.mobility.name == 'driving') {
      return expanded ? 35000 : 20000;
    }
    if (!expanded) return 5000;
    return switch (profile.settlement) {
      SettlementType.historicTown ||
      SettlementType.historicDistrict ||
      SettlementType.village => 15000,
      SettlementType.scenicArea => 20000,
      _ => 12000,
    };
  }

  /// A foreground lightweight refresh must never replace a richer manual brief
  /// for the same region. Location changes are allowed to replace it normally.
  static bool shouldKeepPrevious({
    required RegionBrief? previous,
    required RegionBrief incoming,
    required bool manual,
  }) {
    if (manual || previous == null || previous.regionId != incoming.regionId) {
      return false;
    }
    if (previous.hasUsableFacts && !incoming.hasUsableFacts) return true;
    final previousRank = _completenessRank(previous.completeness);
    final incomingRank = _completenessRank(incoming.completeness);
    if (previousRank != incomingRank) return previousRank > incomingRank;
    final previousEvidence = _evidenceWeight(previous);
    final incomingEvidence = _evidenceWeight(incoming);
    return previousEvidence > incomingEvidence;
  }

  static int _completenessRank(RegionBriefCompleteness value) => switch (value) {
    RegionBriefCompleteness.identityOnly => 0,
    RegionBriefCompleteness.partial => 1,
    RegionBriefCompleteness.actionable => 2,
    RegionBriefCompleteness.comprehensive => 3,
  };

  static int _evidenceWeight(RegionBrief brief) {
    final verified = brief.insights.where((item) {
      return item.verification == InsightVerificationState.authoritative ||
          item.verification == InsightVerificationState.corroborated;
    }).length;
    final strongSources = brief.sources.where((item) {
      return item.qualityTier == InsightQualityTier.s ||
          item.qualityTier == InsightQualityTier.a;
    }).length;
    return brief.insights.length * 4 +
        verified * 3 +
        brief.sources.length * 2 +
        strongSources;
  }
}
