import 'dart:math' as math;

import 'geo_point.dart';

abstract final class GeoDistance {
  static const double _earthRadiusMeters = 6371000;

  static double metersBetween(GeoPoint first, GeoPoint second) {
    final latitudeDelta = _radians(second.latitude - first.latitude);
    final longitudeDelta = _radians(second.longitude - first.longitude);
    final firstLatitude = _radians(first.latitude);
    final secondLatitude = _radians(second.latitude);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    final normalized = haversine.clamp(0.0, 1.0);
    return _earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(normalized), math.sqrt(1 - normalized));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
