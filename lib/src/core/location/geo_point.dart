enum CoordinateSystem { wgs84 }

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  CoordinateSystem get coordinateSystem => CoordinateSystem.wgs84;

  GeoPoint validate() {
    if (latitude < -90 || latitude > 90) {
      throw RangeError.range(latitude, -90, 90, 'latitude');
    }
    if (longitude < -180 || longitude > 180) {
      throw RangeError.range(longitude, -180, 180, 'longitude');
    }
    return this;
  }
}
