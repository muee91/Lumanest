import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';

void main() {
  test('geo point is explicitly WGS84', () {
    const point = GeoPoint(latitude: 31.2304, longitude: 121.4737);

    expect(point.coordinateSystem, CoordinateSystem.wgs84);
  });

  test('latitude outside valid range is rejected', () {
    expect(
      () => const GeoPoint(latitude: 90.1, longitude: 0).validate(),
      throwsRangeError,
    );
  });

  test('longitude outside valid range is rejected', () {
    expect(
      () => const GeoPoint(latitude: 0, longitude: -180.1).validate(),
      throwsRangeError,
    );
  });

  test('location reading preserves observation metadata', () {
    final recordedAt = DateTime.utc(2026, 7, 11, 12);
    final reading = LocationReading(
      point: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      recordedAt: recordedAt,
      accuracyMeters: 8,
      altitudeMeters: 12,
    );

    expect(reading.recordedAt, recordedAt);
    expect(reading.accuracyMeters, 8);
    expect(reading.altitudeMeters, 12);
  });
}
