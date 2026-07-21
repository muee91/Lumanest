import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';

enum RegionBriefStatus { ready, refreshing, partial, pending, unavailable }

enum RegionBriefCompleteness {
  identityOnly,
  partial,
  actionable,
  comprehensive,
}

enum InsightVerificationState {
  authoritative,
  corroborated,
  singleSource,
  candidate,
  conflicting,
}

enum InsightActionability { informational, detail, navigate, remind }

enum RegionInsightType {
  areaIdentity,
  orientation,
  history,
  localStory,
  architecture,
  culturalPractice,
  etiquette,
  performance,
  event,
  market,
  localFood,
  specialty,
  naturalFeature,
  photographyTheme,
  routeStop,
  supply,
  openingStatus,
  regulation,
  seasonalSignal,
}

enum InsightQualityTier { s, a, b, c }

class FactBoundText {
  FactBoundText({required this.summary, required Iterable<String> factIds})
    : factIds = List.unmodifiable(factIds);

  final String summary;
  final List<String> factIds;
}

class InsightEvidence {
  const InsightEvidence({
    required this.id,
    required this.sourcePolicyId,
    required this.publisher,
    required this.title,
    required this.url,
    required this.observedAt,
    required this.qualityTier,
    required this.license,
    required this.version,
    this.publishedAt,
    this.validFrom,
    this.validUntil,
  });

  final String id;
  final String sourcePolicyId;
  final String publisher;
  final String title;
  final Uri url;
  final DateTime observedAt;
  final InsightQualityTier qualityTier;
  final String license;
  final String version;
  final DateTime? publishedAt;
  final DateTime? validFrom;
  final DateTime? validUntil;
}

class RegionInsight {
  RegionInsight({
    required this.id,
    required this.regionId,
    required this.type,
    required this.title,
    required this.summary,
    required this.verification,
    required Iterable<String> factIds,
    required Iterable<String> evidenceIds,
    required this.observedAt,
    required this.expiresAt,
    required this.timeSensitive,
    required this.actionability,
    Iterable<SceneFacet> sceneTags = const {},
    Iterable<String> photoThemeTags = const {},
    this.placeId,
    this.point,
    this.startsAt,
    this.endsAt,
  }) : factIds = List.unmodifiable(factIds),
       evidenceIds = List.unmodifiable(evidenceIds),
       sceneTags = Set.unmodifiable(sceneTags),
       photoThemeTags = Set.unmodifiable(photoThemeTags);

  final String id;
  final String regionId;
  final RegionInsightType type;
  final String title;
  final String summary;
  final InsightVerificationState verification;
  final List<String> factIds;
  final List<String> evidenceIds;
  final DateTime observedAt;
  final DateTime expiresAt;
  final bool timeSensitive;
  final InsightActionability actionability;
  final String? placeId;
  final GeoPoint? point;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final Set<SceneFacet> sceneTags;
  final Set<String> photoThemeTags;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());

  /// Only a reviewed shooting target may become a photography navigation
  /// action. Region insights can otherwise offer detail or reminders.
  bool get canNavigateAsPhotographyTarget => false;
}

class RegionPhotoTheme {
  const RegionPhotoTheme({required this.id, required this.label});

  final String id;
  final String label;
}

class RegionBriefRefresh {
  RegionBriefRefresh({
    required Iterable<String> refreshingMissions,
    required this.retryAfter,
  }) : refreshingMissions = List.unmodifiable(refreshingMissions);

  final List<String> refreshingMissions;
  final Duration? retryAfter;
}

class RegionBrief {
  RegionBrief({
    required this.id,
    required this.regionId,
    required this.regionName,
    required this.profile,
    required this.generatedAt,
    required this.expiresAt,
    required this.status,
    required this.completeness,
    required Iterable<RegionPhotoTheme> photoThemes,
    required Iterable<RegionInsight> insights,
    required Iterable<InsightEvidence> sources,
    required this.refresh,
    this.identity,
    this.orientation,
  }) : photoThemes = List.unmodifiable(photoThemes),
       insights = List.unmodifiable(insights),
       sources = List.unmodifiable(sources);

  final String id;
  final String regionId;
  final String regionName;
  final ExplorationSceneProfile profile;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final RegionBriefStatus status;
  final RegionBriefCompleteness completeness;
  final FactBoundText? identity;
  final FactBoundText? orientation;
  final List<RegionPhotoTheme> photoThemes;
  final List<RegionInsight> insights;
  final List<InsightEvidence> sources;
  final RegionBriefRefresh refresh;

  bool get hasUsableFacts => identity != null && orientation != null;
}
