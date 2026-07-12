import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

void main() {
  test('converts Shanghai WGS84 into the expected GCJ-02 neighborhood', () {
    final converted = ChinaCoordinateConverter.wgs84ToGcj02(
      const GeoPoint(latitude: 31.2304, longitude: 121.4737),
    );

    expect(converted.coordinateSystem, CoordinateSystem.gcj02);
    expect(converted.latitude, closeTo(31.22846, .0001));
    expect(converted.longitude, closeTo(121.47822, .0001));
  });

  test('does not offset points outside mainland China', () {
    final converted = ChinaCoordinateConverter.wgs84ToGcj02(
      const GeoPoint(latitude: 35.6762, longitude: 139.6503),
    );

    expect(converted.latitude, 35.6762);
    expect(converted.longitude, 139.6503);
    expect(converted.coordinateSystem, CoordinateSystem.gcj02);
  });
}
