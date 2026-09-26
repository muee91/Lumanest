import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

enum TargetArrivalState { far, approaching, arrived }

/// A foreground-only distance assessment. A null value means the reading was
/// unavailable or too uncertain to support a user-facing distance claim.
class TargetArrivalAssessment {
  const TargetArrivalAssessment({
    required this.state,
    required this.distanceMeters,
  });

  final TargetArrivalState state;
  final double distanceMeters;
}

abstract final class TargetArrivalStateResolver {
  static const double _maximumReliableAccuracyMeters = 200;

  static TargetArrivalAssessment? assess({
    required GeoPoint? currentPoint,
    required double? accuracyMeters,
    required ShootingTarget target,
  }) {
    final accuracy = accuracyMeters;
    if (currentPoint == null ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > _maximumReliableAccuracyMeters ||
        currentPoint.coordinateSystem != CoordinateSystem.wgs84 ||
        target.coordinate.coordinateSystem != CoordinateSystem.wgs84) {
      return null;
    }

    final distance = GeoDistance.metersBetween(currentPoint, target.coordinate);
    final radius = target.arrivalRadiusMeters;
    if (radius <= 0) return null;
    final approachingRadius = (radius * 3).clamp(800, double.infinity).toDouble();
    final state = distance <= radius
        ? TargetArrivalState.arrived
        : distance <= approachingRadius
        ? TargetArrivalState.approaching
        : TargetArrivalState.far;
    return TargetArrivalAssessment(state: state, distanceMeters: distance);
  }
}
