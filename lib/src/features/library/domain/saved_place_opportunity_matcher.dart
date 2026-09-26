import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

class SavedPlaceOpportunityMatch {
  const SavedPlaceOpportunityMatch({
    required this.placeId,
    required this.sessionId,
    required this.targetId,
    required this.sessionTitle,
    required this.startsAt,
    required this.conditionBand,
  });

  final String placeId;
  final String sessionId;
  final String targetId;
  final String sessionTitle;
  final DateTime startsAt;
  final ShootingConditionBand conditionBand;
}

/// Matches a saved WGS-84 place to a reviewed target using only fresh session
/// evidence. A missing or ambiguous coordinate produces no opportunity.
abstract final class SavedPlaceOpportunityMatcher {
  static SavedPlaceOpportunityMatch? match({
    required SavedPlace place,
    required ContextSnapshot snapshot,
    required DateTime now,
  }) {
    final utcNow = now.toUtc();
    if (snapshot.isStale ||
        snapshot.dataFreshness == ContextDataFreshness.stale ||
        !snapshot.expiresAt.toUtc().isAfter(utcNow)) {
      return null;
    }
    final GeoPoint savedPoint;
    try {
      savedPoint = GeoPoint(
        latitude: place.latitude,
        longitude: place.longitude,
      ).validate();
    } on Object {
      return null;
    }
    final matches = <_Candidate>[];
    for (final session in snapshot.shootingSessions) {
      if (!session.endsAt.toUtc().isAfter(utcNow) ||
          session.isEvidenceExpiredAt(utcNow) ||
          session.conditionBand == ShootingConditionBand.limited ||
          session.confidenceBand == ShootingConfidenceBand.limited) {
        continue;
      }
      for (final target in session.targetCandidates) {
        if (!target.supportedSessions.contains(session.kind) ||
            target.arrivalRadiusMeters <= 0) {
          continue;
        }
        final targetPoint = _normalize(target.coordinate);
        if (targetPoint == null) continue;
        final distance = GeoDistance.metersBetween(savedPoint, targetPoint);
        if (distance <= target.arrivalRadiusMeters) {
          matches.add(_Candidate(session, target, distance));
        }
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((left, right) {
      final time = left.session.startsAt.compareTo(right.session.startsAt);
      if (time != 0) return time;
      final distance = left.distance.compareTo(right.distance);
      if (distance != 0) return distance;
      final session = left.session.id.compareTo(right.session.id);
      return session != 0 ? session : left.target.id.compareTo(right.target.id);
    });
    final winner = matches.first;
    return SavedPlaceOpportunityMatch(
      placeId: place.id,
      sessionId: winner.session.id,
      targetId: winner.target.id,
      sessionTitle: winner.session.title,
      startsAt: winner.session.startsAt,
      conditionBand: winner.session.conditionBand,
    );
  }

  static GeoPoint? _normalize(GeoPoint point) {
    try {
      return point.coordinateSystem == CoordinateSystem.gcj02
          ? ChinaCoordinateConverter.gcj02ToWgs84(point)
          : point.validate();
    } on Object {
      return null;
    }
  }
}

class _Candidate {
  const _Candidate(this.session, this.target, this.distance);
  final ShootingSession session;
  final ShootingTarget target;
  final double distance;
}
