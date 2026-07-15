import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class RouteSupportStop {
  const RouteSupportStop({
    required this.place,
    required this.routeProgress,
    this.cachedAt,
  }) : assert(routeProgress >= 0 && routeProgress <= 1);

  final NearbyPlace place;

  /// Estimated progress of the corridor sample that discovered this place.
  /// This is not a turn-by-turn waypoint and must be described as approximate.
  final double routeProgress;

  /// Set only when restored from the device cache. Cached POIs remain useful
  /// for offline planning but must not be presented as freshly queried data.
  final DateTime? cachedAt;

  bool get isCached => cachedAt != null;
}
