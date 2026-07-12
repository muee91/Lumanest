import 'dart:math' as math;

import 'package:luma_nest/src/core/location/geo_point.dart';

/// Converts WGS84 GPS coordinates to GCJ-02 for mainland AMap services.
/// Coordinates outside mainland China are returned unchanged but explicitly
/// tagged as GCJ-02 so downstream map code never guesses their coordinate type.
abstract final class ChinaCoordinateConverter {
  static const _a = 6378245.0;
  static const _ee = 0.00669342162296594323;

  static GeoPoint wgs84ToGcj02(GeoPoint point) {
    point.validate();
    if (point.coordinateSystem != CoordinateSystem.wgs84) return point;
    if (_outsideMainland(point.latitude, point.longitude)) {
      return GeoPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        coordinateSystem: CoordinateSystem.gcj02,
      );
    }

    var latitudeDelta = _transformLatitude(
      point.longitude - 105,
      point.latitude - 35,
    );
    var longitudeDelta = _transformLongitude(
      point.longitude - 105,
      point.latitude - 35,
    );
    final latitudeRadians = point.latitude / 180 * math.pi;
    var magic = math.sin(latitudeRadians);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    latitudeDelta =
        (latitudeDelta * 180) /
        ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
    longitudeDelta =
        (longitudeDelta * 180) /
        (_a / sqrtMagic * math.cos(latitudeRadians) * math.pi);
    return GeoPoint(
      latitude: point.latitude + latitudeDelta,
      longitude: point.longitude + longitudeDelta,
      coordinateSystem: CoordinateSystem.gcj02,
    );
  }

  static bool _outsideMainland(double latitude, double longitude) =>
      longitude < 72.004 ||
      longitude > 137.8347 ||
      latitude < 0.8293 ||
      latitude > 55.8271;

  static double _transformLatitude(double x, double y) {
    var result =
        -100 +
        2 * x +
        3 * y +
        .2 * y * y +
        .1 * x * y +
        .2 * math.sqrt(x.abs());
    result +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    result +=
        (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3;
    result +=
        (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
        2 /
        3;
    return result;
  }

  static double _transformLongitude(double x, double y) {
    var result =
        300 + x + 2 * y + .1 * x * x + .1 * x * y + .1 * math.sqrt(x.abs());
    result +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    result +=
        (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3;
    result +=
        (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
        2 /
        3;
    return result;
  }
}
