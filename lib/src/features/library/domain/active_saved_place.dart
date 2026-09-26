import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

class ActiveSavedPlaceMatch {
  const ActiveSavedPlaceMatch({
    required this.place,
    required this.session,
    required this.target,
    required this.distanceMeters,
  });

  final SavedPlace place;
  final ShootingSession session;
  final ShootingTarget target;
  final double distanceMeters;
}

/// Matches a user's saved places only against reviewed targets already present
/// in the current, fresh shooting-session contract.
///
/// This is a memory/reactivation layer, not a discovery engine. It never
/// creates a target, widens a reviewed arrival radius, or promotes expired or
/// limited evidence into an opportunity.
abstract final class ActiveSavedPlaceMatcher {
  static List<ActiveSavedPlaceMatch> match({
    required Iterable<SavedPlace> places,
    required Iterable<ShootingSession> sessions,
    required DateTime now,
  }) {
    final utcNow = now.toUtc();
    final validSessions = sessions
        .where(
          (session) =>
              session.endsAt.toUtc().isAfter(utcNow) &&
              !session.isEvidenceExpiredAt(utcNow) &&
              session.confidenceBand != ShootingConfidenceBand.limited &&
              session.conditionBand != ShootingConditionBand.limited &&
              session.targetCandidates.isNotEmpty,
        )
        .toList(growable: false);

    final matches = <ActiveSavedPlaceMatch>[];
    for (final place in places) {
      ActiveSavedPlaceMatch? best;
      for (final session in validSessions) {
        for (final target in session.targetCandidates) {
          if (target.arrivalRadiusMeters <= 0 ||
              !target.supportedSessions.contains(session.kind)) {
            continue;
          }
          final targetPoint = ChinaCoordinateConverter.gcj02ToWgs84(
            target.coordinate,
          );
          final distance = GeoDistance.metersBetween(place.point, targetPoint);
          if (distance > target.arrivalRadiusMeters) continue;
          final candidate = ActiveSavedPlaceMatch(
            place: place,
            session: session,
            target: target,
            distanceMeters: distance,
          );
          if (best == null || _prefer(candidate, best, utcNow)) {
            best = candidate;
          }
        }
      }
      if (best != null) matches.add(best);
    }

    matches.sort((left, right) {
      final time = left.session.presentationStartsAt.compareTo(
        right.session.presentationStartsAt,
      );
      if (time != 0) return time;
      final distance = left.distanceMeters.compareTo(right.distanceMeters);
      return distance != 0 ? distance : left.place.id.compareTo(right.place.id);
    });
    return List.unmodifiable(matches);
  }

  static bool _prefer(
    ActiveSavedPlaceMatch candidate,
    ActiveSavedPlaceMatch current,
    DateTime now,
  ) {
    final candidateActive =
        !now.isBefore(candidate.session.startsAt.toUtc()) &&
        now.isBefore(candidate.session.endsAt.toUtc());
    final currentActive =
        !now.isBefore(current.session.startsAt.toUtc()) &&
        now.isBefore(current.session.endsAt.toUtc());
    if (candidateActive != currentActive) return candidateActive;

    final candidateGood =
        candidate.session.conditionBand == ShootingConditionBand.good;
    final currentGood =
        current.session.conditionBand == ShootingConditionBand.good;
    if (candidateGood != currentGood) return candidateGood;

    final time = candidate.session.presentationStartsAt.compareTo(
      current.session.presentationStartsAt,
    );
    if (time != 0) return time < 0;
    return candidate.distanceMeters < current.distanceMeters;
  }
}
