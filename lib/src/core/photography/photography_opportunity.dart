import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

/// Local, explainable photography decision values.
///
/// These models intentionally have no transport, AI, or user-identity fields.
/// They describe an opportunity that has already been established by context
/// rules; they never establish weather or safety facts themselves.
enum PhotographyDecision { go, wait, stay, move, returnHome, skip }

enum PhotographyEvidenceKind {
  light,
  weather,
  astronomy,
  place,
  route,
  equipment,
}

/// The bounded server-established opportunity categories. These are not user
/// preferences and cannot be extended by model output.
enum PhotographyOpportunityKind {
  blueHour,
  reflection,
  alpenglow,
  morningMist,
  sunsetGlow,
  astronomy,
}

enum PhotographyOpportunityGeoScope { point, regional, route }

enum PhotographyTargetKind { viewpoint, lakeshore, trailhead, urban }

/// An approved target attached to an already-established opportunity. It is
/// optional so V3 responses remain valid and it never becomes a discovery API.
class PhotographyTarget {
  const PhotographyTarget({
    required this.id,
    required this.name,
    required this.kind,
    required this.coordinate,
    required this.arrivalDeadline,
  });

  final String id;
  final String name;
  final PhotographyTargetKind kind;
  final GeoPoint coordinate;
  final DateTime arrivalDeadline;
}

class PhotographyCorridorObservation {
  const PhotographyCorridorObservation({
    required this.progress,
    required this.expectedAt,
    required this.condition,
    required this.windSpeedMps,
    required this.precipitationMm,
    required this.thunder,
    this.cloudCoverPercent,
    this.sunAzimuthDegrees,
    this.opportunityId,
  });

  final double progress;
  final DateTime expectedAt;
  final String condition;
  final double windSpeedMps;
  final double precipitationMm;
  final bool thunder;
  final double? cloudCoverPercent;
  final double? sunAzimuthDegrees;
  final String? opportunityId;
}

class PhotographyCorridor {
  PhotographyCorridor({
    required this.routeId,
    required Iterable<PhotographyCorridorObservation> observations,
  }) : observations = List.unmodifiable(observations);

  final String routeId;
  final List<PhotographyCorridorObservation> observations;
}

class PhotographyEvidence {
  const PhotographyEvidence({
    required this.id,
    required this.kind,
    required this.statement,
    required this.confidence,
    this.supports = true,
  }) : assert(confidence >= 0 && confidence <= 1);

  final String id;
  final PhotographyEvidenceKind kind;

  /// A short, already-established factual basis for the opportunity.
  final String statement;
  final double confidence;
  final bool supports;

  @override
  bool operator ==(Object other) =>
      other is PhotographyEvidence &&
      other.id == id &&
      other.kind == kind &&
      other.statement == statement &&
      other.confidence == confidence &&
      other.supports == supports;

  @override
  int get hashCode => Object.hash(id, kind, statement, confidence, supports);
}

/// A deterministic local recommendation. This is not a safety decision.
class PhotographyOpportunity {
  PhotographyOpportunity({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.peaksAt,
    required this.expiresAt,
    required this.confidence,
    required Iterable<PhotographyEvidence> evidence,
    this.kind = PhotographyOpportunityKind.sunsetGlow,
    this.score = 0,
    this.geoScope = PhotographyOpportunityGeoScope.point,
    this.directionDegrees,
    this.primaryAction,
    this.fallbackAction,
    Iterable<String> equipmentHints = const <String>[],
    Iterable<String> requiredCapabilities = const <String>[],
    this.isAtCurrentLocation = false,
    this.isReturnJourney = false,
    this.target,
    this.corridor,
  }) : assert(confidence >= 0 && confidence <= 1),
       assert(score >= 0 && score <= 100),
       assert(
         directionDegrees == null ||
             (directionDegrees >= 0 && directionDegrees < 360),
       ),
       assert(!peaksAt.isBefore(startsAt)),
       assert(!expiresAt.isBefore(peaksAt)),
       evidence = List.unmodifiable(evidence),
       equipmentHints = List.unmodifiable(
         equipmentHints
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       ),
       requiredCapabilities = Set.unmodifiable(
         requiredCapabilities
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       );

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime peaksAt;
  final DateTime expiresAt;
  final double confidence;
  final List<PhotographyEvidence> evidence;
  final PhotographyOpportunityKind kind;
  final int score;
  final PhotographyOpportunityGeoScope geoScope;
  final double? directionDegrees;
  final ContextAction? primaryAction;
  final ContextAction? fallbackAction;

  /// Server-approved, display-ready hints. They never contain profile data
  /// and are intentionally separate from hard capability requirements.
  final List<String> equipmentHints;

  /// Canonical capability IDs, for example `tripod` or `wide_angle`.
  final Set<String> requiredCapabilities;
  final bool isAtCurrentLocation;
  final bool isReturnJourney;
  final PhotographyTarget? target;
  final PhotographyCorridor? corridor;

  bool isActiveAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(expiresAt);

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  @override
  bool operator ==(Object other) =>
      other is PhotographyOpportunity &&
      other.id == id &&
      other.title == title &&
      other.startsAt == startsAt &&
      other.peaksAt == peaksAt &&
      other.expiresAt == expiresAt &&
      other.confidence == confidence &&
      other.kind == kind &&
      other.score == score &&
      other.geoScope == geoScope &&
      other.directionDegrees == directionDegrees &&
      other.primaryAction == primaryAction &&
      other.fallbackAction == fallbackAction &&
      other.isAtCurrentLocation == isAtCurrentLocation &&
      other.isReturnJourney == isReturnJourney &&
      _listEquals(other.equipmentHints, equipmentHints) &&
      _setEquals(other.requiredCapabilities, requiredCapabilities) &&
      _listEquals(other.evidence, evidence);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    startsAt,
    peaksAt,
    expiresAt,
    confidence,
    kind,
    score,
    geoScope,
    directionDegrees,
    primaryAction,
    fallbackAction,
    Object.hashAll(evidence),
    Object.hashAll(equipmentHints),
    Object.hashAllUnordered(requiredCapabilities),
    isAtCurrentLocation,
    isReturnJourney,
  );
}

class PhotographyDecisionResolution {
  PhotographyDecisionResolution({
    required this.decision,
    required this.score,
    required this.actionLabel,
    required this.reason,
    List<String> missingCapabilities = const <String>[],
  }) : missingCapabilities = List.unmodifiable(missingCapabilities);

  final PhotographyDecision decision;
  final int score;
  final String actionLabel;
  final String reason;
  final List<String> missingCapabilities;
}

abstract final class PhotographyDecisionResolver {
  /// Scores only established evidence and local equipment readiness. A missing
  /// item can lower a recommendation but can never manufacture an opportunity.
  static PhotographyDecisionResolution resolve(
    PhotographyOpportunity opportunity, {
    required DateTime now,
    Iterable<String> availableCapabilities = const <String>[],
  }) {
    final available = availableCapabilities.toSet();
    final missing = opportunity.requiredCapabilities
        .where((capability) => !available.contains(capability))
        .toList(growable: false);
    final score = _score(opportunity, missing);

    if (opportunity.isExpiredAt(now)) {
      return PhotographyDecisionResolution(
        decision: PhotographyDecision.skip,
        score: score,
        actionLabel: '窗口已结束',
        reason: '不再推荐为此窗口出发。',
        missingCapabilities: missing,
      );
    }
    if (score < 40) {
      return PhotographyDecisionResolution(
        decision: PhotographyDecision.skip,
        score: score,
        actionLabel: '先不出发',
        reason: '当前成立依据不足。',
        missingCapabilities: missing,
      );
    }
    if (opportunity.isReturnJourney &&
        opportunity.expiresAt.difference(now) <= const Duration(minutes: 20)) {
      return PhotographyDecisionResolution(
        decision: PhotographyDecision.returnHome,
        score: score,
        actionLabel: '开始返程',
        reason: '窗口接近结束，优先保留返程时间。',
        missingCapabilities: missing,
      );
    }
    if (missing.isNotEmpty) {
      return PhotographyDecisionResolution(
        decision: PhotographyDecision.move,
        score: score,
        actionLabel: '换机位',
        reason: '当前装备不匹配，选择不依赖它的机位。',
        missingCapabilities: missing,
      );
    }
    if (now.isBefore(opportunity.startsAt)) {
      return PhotographyDecisionResolution(
        decision: PhotographyDecision.wait,
        score: score,
        actionLabel: '开始守候',
        reason: '窗口尚未开始。',
      );
    }
    if (opportunity.isAtCurrentLocation) {
      return PhotographyDecisionResolution(
        decision: PhotographyDecision.stay,
        score: score,
        actionLabel: '就地拍摄',
        reason: '当前位置已经进入有效窗口。',
      );
    }
    return PhotographyDecisionResolution(
      decision: PhotographyDecision.go,
      score: score,
      actionLabel: '立即出发',
      reason: '条件与装备均匹配。',
    );
  }

  static int _score(PhotographyOpportunity opportunity, List<String> missing) {
    final support = opportunity.evidence
        .where((item) => item.supports)
        .fold<double>(0, (score, item) => score + item.confidence * 8);
    final contrary = opportunity.evidence
        .where((item) => !item.supports)
        .fold<double>(0, (score, item) => score + item.confidence * 10);
    final result =
        opportunity.confidence * 80 + support - contrary - missing.length * 12;
    return result.round().clamp(0, 100);
  }
}

bool _setEquals<T>(Set<T> first, Set<T> second) =>
    first.length == second.length && first.containsAll(second);

bool _listEquals<T>(List<T> first, List<T> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
