import 'package:luma_nest/src/core/location/geo_point.dart';

class LocationReading {
  const LocationReading({
    required this.point,
    required this.recordedAt,
    required this.accuracyMeters,
    this.altitudeMeters,
  });

  final GeoPoint point;
  final DateTime recordedAt;
  final double accuracyMeters;
  final double? altitudeMeters;
}
