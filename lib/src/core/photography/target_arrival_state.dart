import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

enum TargetArrivalState { far, approaching, arrived }

class TargetArrivalAssessment {
  const TargetArrivalAssessment({
    required this.state,
    required this.distanceMeters,
    required this.accuracyMeters,
  });

  final TargetArrivalState state;
  final double distanceMeters;
  final double accuracyMeters;

  bool get isArrived => state == TargetArrivalState.arrived;
}

/// Conservative foreground-only arrival assessment.
///
/// The reading must be recent and accurate enough for the reviewed target
/// radius. Arrival is asserted only when the whole reported horizontal
/// uncertainty still fits inside the target radius.
abstract final class TargetArrivalStateResolver {
  static const Duration maximumReadingAge = Duration(minutes: 2);
  static const Duration maximumFutureSkew = Duration(seconds: 30);
  static const double maximumAccuracyMeters = 100;

  static TargetArrivalAssessment? assess({
    required LocationReading? reading,
    required ShootingTarget target,
    required DateTime now,
  }) {
    if (reading == null || target.arrivalRadiusMeters <= 0) return null;

    final accuracy = reading.accuracyMeters;
    if (!accuracy.isFinite || accuracy < 0) return null;

    final radius = target.arrivalRadiusMeters.toDouble();
    final allowedAccuracy =
        radius < maximumAccuracyMeters ? radius : maximumAccuracyMeters;
    if (accuracy > allowedAccuracy) return null;

    final utcNow = now.toUtc();
    final recordedAt = reading.recordedAt.toUtc();
    if (recordedAt.isBefore(utcNow.subtract(maximumReadingAge)) ||
        recordedAt.isAfter(utcNow.add(maximumFutureSkew))) {
      return null;
    }

    try {
      final current = ChinaCoordinateConverter.gcj02ToWgs84(
        reading.point,
      ).validate();
      final targetPoint = ChinaCoordinateConverter.gcj02ToWgs84(
        target.coordinate,
      ).validate();
      final distance = GeoDistance.metersBetween(current, targetPoint);
      final conservativeDistance = distance + accuracy;
      final approachingRadius =
          radius * 3 > 800 ? radius * 3 : 800.0;
      final state = conservativeDistance <= radius
          ? TargetArrivalState.arrived
          : distance <= approachingRadius
          ? TargetArrivalState.approaching
          : TargetArrivalState.far;
      return TargetArrivalAssessment(
        state: state,
        distanceMeters: distance,
        accuracyMeters: accuracy,
      );
    } on Object {
      return null;
    }
  }
}
