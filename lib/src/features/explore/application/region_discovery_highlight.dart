import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

class RegionDiscoveryHighlight {
  const RegionDiscoveryHighlight({
    required this.regionName,
    required this.title,
    required this.summary,
    required this.timeSensitive,
  });

  final String regionName;
  final String title;
  final String summary;
  final bool timeSensitive;
}

/// Selects one source-bound regional finding for Today.
///
/// Identity-only briefs remain in Explore. Today only surfaces a concrete,
/// unexpired finding that passed verification and offers a next step.
RegionDiscoveryHighlight? selectRegionDiscoveryHighlight(
  RegionBrief? brief, {
  required DateTime now,
}) {
  if (brief?.hasUsableFacts != true) {
    return null;
  }
  final candidates = brief!.insights
      .where((insight) {
        if (insight.type == RegionInsightType.areaIdentity ||
            insight.type == RegionInsightType.orientation) {
          return false;
        }
        if (insight.isExpiredAt(now) || insight.evidenceIds.isEmpty) {
          return false;
        }
        if (insight.verification == InsightVerificationState.candidate ||
            insight.verification == InsightVerificationState.conflicting) {
          return false;
        }
        return insight.actionability != InsightActionability.informational ||
            insight.timeSensitive;
      })
      .toList(growable: false);
  if (candidates.isEmpty) {
    return null;
  }
  final ranked = [...candidates]
    ..sort((left, right) {
      final priority = _priority(left).compareTo(_priority(right));
      if (priority != 0) return priority;
      final time = right.observedAt.compareTo(left.observedAt);
      if (time != 0) return time;
      return left.id.compareTo(right.id);
    });
  final selected = ranked.first;
  return RegionDiscoveryHighlight(
    regionName: brief.regionName,
    title: selected.title,
    summary: selected.summary,
    timeSensitive: selected.timeSensitive,
  );
}

int _priority(RegionInsight insight) {
  if (insight.timeSensitive &&
      insight.actionability == InsightActionability.remind) {
    return 0;
  }
  if (insight.timeSensitive) return 1;
  if (insight.actionability == InsightActionability.remind) return 2;
  return 3;
}
