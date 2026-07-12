enum CoordinateSystem { wgs84, gcj02 }

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.coordinateSystem = CoordinateSystem.wgs84,
  });

  final double latitude;
  final double longitude;
  final CoordinateSystem coordinateSystem;

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
