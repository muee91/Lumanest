import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_context.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

abstract final class NearbyDiscoveryPolicy {
  static List<NearbyPlace> hardFilter(
    Iterable<NearbyPlace> places,
    NearbyDiscoveryContext context,
  ) {
    final safetyActive = context.snapshot.events.any(
      (event) =>
          (event.channel == ContextEventChannel.safety ||
              event.channel == ContextEventChannel.wildlifeSafety) &&
          !event.isExpiredAt(context.now),
    );
    final activeWindow = context.snapshot.shootingSessions
        .where((session) => session.endsAt.isAfter(context.now))
        .fold<Duration?>(null, (shortest, session) {
          final remaining = session.endsAt.difference(context.now);
          return shortest == null || remaining < shortest
              ? remaining
              : shortest;
        });
    return places
        .where((place) {
          if (place.distanceMeters < 0 ||
              place.distanceMeters > context.radiusMeters * 2) {
            return false;
          }
          if (context.intent == NearbyPlaceCategory.humanity &&
              !place.hasHumanityEvidence) {
            return false;
          }
          if (context.mode == NearbyDiscoveryMode.passive && safetyActive) {
            final utility = {
              NearbyPlaceCategory.medical,
              NearbyPlaceCategory.fuel,
              NearbyPlaceCategory.supply,
            };
            if (!utility.contains(place.category)) return false;
          }
          final drive = place.drivingDurationSeconds;
          if (activeWindow != null &&
              context.intent == NearbyPlaceCategory.viewpoint &&
              drive != null &&
              Duration(seconds: drive) > activeWindow) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  static double score(NearbyPlace place, NearbyDiscoveryContext context) {
    final boundedRadius = context.radiusMeters.clamp(100, 50000);
    final drive = place.drivingDurationSeconds;
    final accessibility = drive == null
        ? 10
        : (25 * (1 - drive / 7200).clamp(0.0, 1.0));
    final environment = switch (context.intent) {
      NearbyPlaceCategory.food ||
      NearbyPlaceCategory.fuel ||
      NearbyPlaceCategory.supply ||
      NearbyPlaceCategory.medical => 15,
      _ => _environmentFit(context),
    };
    final evidence = (place.sourceEvidenceCount.clamp(0, 3) / 3) * 15;
    final intent = place.category == context.intent ? 15 : 8;
    final distance =
        (1 - place.distanceMeters / boundedRadius).clamp(0.0, 1.0) * 10;
    final route =
        context.snapshot.activeRoute &&
            place.category == NearbyPlaceCategory.parking
        ? 5
        : 0;
    final freshness = place.isOfflineCache ? 2 : 5;
    return accessibility +
        environment +
        evidence +
        intent +
        distance +
        route +
        freshness;
  }

  static double _environmentFit(NearbyDiscoveryContext context) {
    final snapshot = context.snapshot;
    if (snapshot.isStale) return 4;
    if (snapshot.weather == WeatherType.rain ||
        snapshot.weather == WeatherType.snow) {
      return 5;
    }
    if (snapshot.windSpeedMetersPerSecond case final wind? when wind > 10) {
      return 6;
    }
    return 16;
  }

  static int limit(NearbyDiscoveryMode mode) => switch (mode) {
    NearbyDiscoveryMode.passive => 3,
    NearbyDiscoveryMode.explicit => 16,
    NearbyDiscoveryMode.routeCorridor => 8,
  };

  static double threshold(NearbyDiscoveryMode mode) => switch (mode) {
    NearbyDiscoveryMode.passive => 65,
    NearbyDiscoveryMode.explicit => 35,
    NearbyDiscoveryMode.routeCorridor => 45,
  };
}
