/// Coordinate systems carried by external and persisted location values.
///
/// `unknown` is intentionally explicit. It is used for pre-schema-19 saved
/// places whose old coordinates cannot be safely identified as WGS-84 or
/// GCJ-02. Callers must not pass it to a provider or use it for distance
/// matching until the user saves the place again from a canonical source.
enum CoordinateSystem { wgs84, gcj02, unknown }

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
