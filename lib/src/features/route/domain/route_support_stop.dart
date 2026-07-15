import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class RouteSupportStop {
  const RouteSupportStop({required this.place, required this.routeProgress})
    : assert(routeProgress >= 0 && routeProgress <= 1);

  final NearbyPlace place;

  /// Estimated progress of the corridor sample that discovered this place.
  /// This is not a turn-by-turn waypoint and must be described as approximate.
  final double routeProgress;
}
