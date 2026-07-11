import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

class SolarState {
  const SolarState({
    required this.observedAt,
    required this.elevationDegrees,
    required this.azimuthDegrees,
    required this.sunrise,
    required this.sunset,
    required this.dayPhase,
  });

  final DateTime observedAt;
  final double elevationDegrees;
  final double azimuthDegrees;
  final DateTime? sunrise;
  final DateTime? sunset;
  final DayPhase dayPhase;
}

abstract interface class SolarService {
  SolarState calculate({
    required GeoPoint point,
    required DateTime moment,
    required Duration utcOffset,
    double altitudeMeters = 0,
  });
}
