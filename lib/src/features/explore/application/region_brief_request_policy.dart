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

  static const _verificationPriority = <String>[
    'practical',
    'happeningNow',
    'places',
    'photoThemes',
    'localTaste',
    'etiquette',
    'identity',
    'orientation',
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

  static RegionBriefRequestPlan verificationPlan(
    ExplorationSceneProfile profile,
    RegionBrief brief,
  ) => RegionBriefRequestPlan(
    activationType: 'ai_verification',
    radiusMeters: _verificationRadius(profile),
    requestedSections: verificationSections(brief),
    expanded: false,
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

  static bool needsVerification(RegionBrief? brief) =>
      brief != null && verificationSections(brief).isNotEmpty;

  static int verificationTargetCount(RegionBrief? brief) {
    if (brief == null) return 0;
    return brief.insights.where(_needsVerification).length;
  }

  static List<String> verificationSections(RegionBrief brief) {
    final requested = <String>{};
    for (final insight in brief.insights.where(_needsVerification)) {
      requested.add(_sectionFor(insight.type));
    }
    return _verificationPriority
        .where(requested.contains)
        .take(4)
        .toList(growable: false);
  }

  /// Pending or unavailable refreshes never erase a usable brief for the same
  /// region. A lightweight foreground refresh also cannot downgrade a richer
  /// manual result. Verification is adopted only when it reduces evidence
  /// debt without deleting facts or sources.
  static bool shouldKeepPrevious({
    required RegionBrief? previous,
    required RegionBrief incoming,
    required bool manual,
    bool verification = false,
  }) {
    if (previous == null || previous.regionId != incoming.regionId) return false;
    if (previous.hasUsableFacts && !incoming.hasUsableFacts) return true;
    if (verification) return !_verificationImproved(previous, incoming);
    if (manual) return false;
    final previousRank = _completenessRank(previous.completeness);
    final incomingRank = _completenessRank(incoming.completeness);
    if (previousRank != incomingRank) return previousRank > incomingRank;
    final previousEvidence = _evidenceWeight(previous);
    final incomingEvidence = _evidenceWeight(incoming);
    return previousEvidence > incomingEvidence;
  }

  static bool _verificationImproved(
    RegionBrief previous,
    RegionBrief incoming,
  ) {
    if (!incoming.hasUsableFacts ||
        _completenessRank(incoming.completeness) <
            _completenessRank(previous.completeness) ||
        incoming.insights.length < previous.insights.length ||
        incoming.sources.length < previous.sources.length) {
      return false;
    }
    final previousDebt = _verificationDebt(previous);
    final incomingDebt = _verificationDebt(incoming);
    if (incomingDebt < previousDebt) return true;
    return incomingDebt == previousDebt &&
        _evidenceWeight(incoming) > _evidenceWeight(previous);
  }

  static bool _needsVerification(RegionInsight insight) =>
      insight.verification == InsightVerificationState.candidate ||
      insight.verification == InsightVerificationState.conflicting ||
      insight.timeSensitive &&
          insight.verification == InsightVerificationState.singleSource;

  static int _verificationRadius(ExplorationSceneProfile profile) {
    if (profile.remoteness == RemotenessLevel.remote ||
        profile.remoteness == RemotenessLevel.extreme) {
      return 50000;
    }
    if (profile.mobility.name == 'driving') return 25000;
    return switch (profile.settlement) {
      SettlementType.historicTown ||
      SettlementType.historicDistrict ||
      SettlementType.village => 15000,
      SettlementType.scenicArea => 20000,
      _ => 12000,
    };
  }

  static String _sectionFor(RegionInsightType type) => switch (type) {
    RegionInsightType.areaIdentity ||
    RegionInsightType.history ||
    RegionInsightType.localStory => 'identity',
    RegionInsightType.orientation => 'orientation',
    RegionInsightType.architecture ||
    RegionInsightType.naturalFeature ||
    RegionInsightType.photographyTheme ||
    RegionInsightType.seasonalSignal => 'photoThemes',
    RegionInsightType.performance ||
    RegionInsightType.event ||
    RegionInsightType.market => 'happeningNow',
    RegionInsightType.routeStop => 'places',
    RegionInsightType.localFood || RegionInsightType.specialty => 'localTaste',
    RegionInsightType.culturalPractice || RegionInsightType.etiquette =>
      'etiquette',
    RegionInsightType.supply ||
    RegionInsightType.openingStatus ||
    RegionInsightType.regulation => 'practical',
  };

  static int _verificationDebt(RegionBrief brief) => brief.insights.fold(
    0,
    (total, insight) =>
        total +
        switch (insight.verification) {
          InsightVerificationState.conflicting => 6,
          InsightVerificationState.candidate => 4,
          InsightVerificationState.singleSource when insight.timeSensitive => 3,
          InsightVerificationState.singleSource => 1,
          InsightVerificationState.authoritative ||
          InsightVerificationState.corroborated => 0,
        },
  );

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
