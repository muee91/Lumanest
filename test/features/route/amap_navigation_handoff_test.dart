import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/application/amap_navigation_handoff.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

void main() {
  test('builds a GCJ-02 AMap handoff URI from canonical WGS84 destination', () {
    const wgs84 = GeoPoint(latitude: 30.2741, longitude: 120.1551);
    final expected = ChinaCoordinateConverter.wgs84ToGcj02(wgs84);

    final uri = UrlLauncherAmapNavigationHandoff.buildNativeUri(
      destinationName: '西湖',
      destination: wgs84,
      mode: RouteTravelMode.driving,
    );

    expect(uri.scheme, 'androidamap');
    expect(uri.host, 'route');
    expect(uri.queryParameters['dlat'], '${expected.latitude}');
    expect(uri.queryParameters['dlon'], '${expected.longitude}');
    expect(uri.queryParameters['dname'], '西湖');
    expect(uri.queryParameters['t'], '0');
  });

  test('keeps an existing GCJ-02 point and encodes walking mode', () {
    const gcj02 = GeoPoint(
      latitude: 30.276,
      longitude: 120.16,
      coordinateSystem: CoordinateSystem.gcj02,
    );

    final uri = UrlLauncherAmapNavigationHandoff.buildWebUri(
      destinationName: '徒步入口',
      destination: gcj02,
      mode: RouteTravelMode.walking,
    );

    expect(uri.host, 'uri.amap.com');
    expect(uri.queryParameters['to'], '120.16,30.276,徒步入口');
    expect(uri.queryParameters['mode'], 'walk');
    expect(uri.queryParameters['coordinate'], 'gaode');
  });
}
