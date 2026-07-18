import 'dart:math' as math;

import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';

enum GeoScope { point, region, route }

class OpportunityEvidence {
  const OpportunityEvidence({
    required this.kind,
    required this.observedAt,
    required this.expiresAt,
    required this.confidence,
    required this.sourceId,
  }) : assert(confidence >= 0 && confidence <= 1);

  final EvidenceKind kind;
  final DateTime observedAt;
  final DateTime expiresAt;
  final double confidence;
  final String sourceId;

  bool isFreshAt(DateTime moment) => expiresAt.isAfter(moment);
}

class OpportunityInstance {
  OpportunityInstance({
    required this.instanceId,
    required this.definitionId,
    required this.startsAt,
    required this.expiresAt,
    required this.evidenceExpiresAt,
    required this.confidence,
    required this.geoScope,
    required Iterable<OpportunityEvidence> evidence,
    this.peaksAt,
    this.targetId,
    this.routeId,
    this.sessionId,
    this.directionDegrees,
    this.reviewedTarget = false,
    this.routeRelevant = false,
    this.estimatedArrivalAt,
    this.lastShownAt,
  }) : assert(confidence >= 0 && confidence <= 1),
       assert(!expiresAt.isBefore(startsAt)),
       assert(peaksAt == null || !peaksAt.isBefore(startsAt)),
       assert(peaksAt == null || !expiresAt.isBefore(peaksAt)),
       assert(!evidenceExpiresAt.isAfter(expiresAt)),
       assert(
         directionDegrees == null ||
             (directionDegrees >= 0 && directionDegrees < 360),
       ),
       evidence = List.unmodifiable(evidence);

  final String instanceId;
  final String definitionId;
  final DateTime startsAt;
  final DateTime? peaksAt;
  final DateTime expiresAt;
  final DateTime evidenceExpiresAt;
  final double confidence;
  final GeoScope geoScope;
  final List<OpportunityEvidence> evidence;
  final String? targetId;
  final String? routeId;
  final String? sessionId;
  final double? directionDegrees;
  final bool reviewedTarget;
  final bool routeRelevant;
  final DateTime? estimatedArrivalAt;
  final DateTime? lastShownAt;

  Set<EvidenceKind> freshEvidenceKindsAt(DateTime moment) => evidence
      .where((item) => item.isFreshAt(moment))
      .map((item) => item.kind)
      .toSet();
}

class RankedOpportunity {
  const RankedOpportunity({required this.instance, required this.score});

  final OpportunityInstance instance;
  final double score;
}

abstract final class OpportunityRanker {
  static List<RankedOpportunity> rank({
    required Iterable<OpportunityInstance> instances,
    required OpportunityCatalog catalog,
    required SceneContext sceneContext,
    required DateTime now,
    Set<String> activeSafetyConflicts = const <String>{},
    Set<PhotographyPreferenceId> preferences =
        const <PhotographyPreferenceId>{},
  }) {
    final ranked =
        instances
            .expand((instance) {
              final definition = catalog.byId[instance.definitionId];
              if (definition == null ||
                  !_passesHardFilters(
                    instance: instance,
                    definition: definition,
                    now: now,
                    safety: activeSafetyConflicts,
                  )) {
                return const <RankedOpportunity>[];
              }
              return [
                RankedOpportunity(
                  instance: instance,
                  score: _score(
                    instance: instance,
                    definition: definition,
                    sceneContext: sceneContext,
                    now: now,
                    preferences: preferences,
                  ),
                ),
              ];
            })
            .toList(growable: false)
          ..sort((left, right) {
            final score = right.score.compareTo(left.score);
            if (score != 0) return score;
            final leftPeak = left.instance.peaksAt ?? left.instance.expiresAt;
            final rightPeak =
                right.instance.peaksAt ?? right.instance.expiresAt;
            final peak = leftPeak.compareTo(rightPeak);
            if (peak != 0) return peak;
            final definition = left.instance.definitionId.compareTo(
              right.instance.definitionId,
            );
            if (definition != 0) return definition;
            return left.instance.instanceId.compareTo(
              right.instance.instanceId,
            );
          });

    final selected = <RankedOpportunity>[];
    for (final candidate in ranked) {
      final isSuppressed = selected.any(
        (winner) =>
            _suppresses(winner.instance, candidate.instance, catalog: catalog),
      );
      if (!isSuppressed) selected.add(candidate);
    }
    return List.unmodifiable(selected);
  }

  static bool _passesHardFilters({
    required OpportunityInstance instance,
    required OpportunityDefinition definition,
    required DateTime now,
    required Set<String> safety,
  }) {
    if (definition.catalogTier != CatalogTier.core ||
        definition.coreCapability == CoreCapabilityState.unavailable ||
        definition.safetyConflicts.any(safety.contains) ||
        instance.confidence < (definition.minimumConfidence ?? 1) ||
        !instance.expiresAt.isAfter(now) ||
        !instance.evidenceExpiresAt.isAfter(now)) {
      return false;
    }
    final evidenceKinds = instance.freshEvidenceKindsAt(now);
    if (!evidenceKinds.containsAll(definition.requiredEvidence)) return false;
    if (instance.estimatedArrivalAt != null &&
        instance.estimatedArrivalAt!.isAfter(instance.expiresAt)) {
      return false;
    }
    return true;
  }

  static double _score({
    required OpportunityInstance instance,
    required OpportunityDefinition definition,
    required SceneContext sceneContext,
    required DateTime now,
    required Set<PhotographyPreferenceId> preferences,
  }) {
    var score = instance.confidence * 50;
    final peak = instance.peaksAt;
    if (peak != null) {
      final untilPeak = peak.difference(now);
      if (!untilPeak.isNegative && untilPeak <= const Duration(minutes: 30)) {
        score += 20;
      } else if (!untilPeak.isNegative &&
          untilPeak <= const Duration(minutes: 90)) {
        score += 15;
      } else if (!untilPeak.isNegative &&
          untilPeak <= const Duration(hours: 3)) {
        score += 10;
      } else if (!untilPeak.isNegative &&
          untilPeak <= const Duration(hours: 12)) {
        score += 5;
      }
    }
    if (definition.primaryScenes.contains(sceneContext.primaryScene)) {
      score += 10;
    }
    if (definition.preferenceAffinities.any(preferences.contains)) score += 8;
    if (instance.routeRelevant) score += 7;
    if (instance.reviewedTarget) score += 5;
    if (instance.evidence.every((item) => item.isFreshAt(now))) score += 5;
    if (instance.lastShownAt != null &&
        now.difference(instance.lastShownAt!) < const Duration(hours: 24)) {
      score -= 8;
    }
    return score;
  }

  static bool _suppresses(
    OpportunityInstance winner,
    OpportunityInstance candidate, {
    required OpportunityCatalog catalog,
  }) {
    final definition = catalog.byId[winner.definitionId];
    if (definition == null ||
        !definition.suppresses.contains(candidate.definitionId) ||
        !_overlapsAtLeastHalf(winner, candidate)) {
      return false;
    }
    if (candidate.definitionId != 'event.sky.sunset_glow') return true;
    if (winner.definitionId == 'session.city.blue_hour') {
      return winner.targetId != null && winner.targetId == candidate.targetId;
    }
    if (winner.directionDegrees == null || candidate.directionDegrees == null) {
      return false;
    }
    final difference = (winner.directionDegrees! - candidate.directionDegrees!)
        .abs();
    return math.min(difference, 360 - difference) <= 20;
  }

  static bool _overlapsAtLeastHalf(
    OpportunityInstance left,
    OpportunityInstance right,
  ) {
    final start = left.startsAt.isAfter(right.startsAt)
        ? left.startsAt
        : right.startsAt;
    final end = left.expiresAt.isBefore(right.expiresAt)
        ? left.expiresAt
        : right.expiresAt;
    if (!end.isAfter(start)) return false;
    final overlap = end.difference(start);
    final shorter =
        left.expiresAt.difference(left.startsAt) <
            right.expiresAt.difference(right.startsAt)
        ? left.expiresAt.difference(left.startsAt)
        : right.expiresAt.difference(right.startsAt);
    return overlap.inMilliseconds >= shorter.inMilliseconds * 0.5;
  }
}
