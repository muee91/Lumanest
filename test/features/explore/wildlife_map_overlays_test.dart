import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/presentation/wildlife_map_overlays.dart';

void main() {
  test(
    'converts WGS84 rings only for AMap rendering and keeps a stable id',
    () {
      const first = GeoPoint(latitude: 31.2304, longitude: 121.4737);
      final areaId = List.filled(64, 'a').join();
      final layer = WildlifeMapLayer(
        generatedAt: DateTime.utc(2026, 7, 16),
        radiusKilometers: 20,
        areas: [
          WildlifeMapArea(
            id: areaId,
            name: '历史观察区域',
            polygons: const [
              [
                first,
                GeoPoint(latitude: 31.2304, longitude: 121.4837),
                GeoPoint(latitude: 31.2404, longitude: 121.4837),
                first,
              ],
            ],
            source: const WildlifeMapAreaSource(
              attribution: 'Reviewed fixture',
              version: '1',
            ),
          ),
        ],
      );

      final polygon = buildWildlifeMapPolygons(layer).single;

      expect(polygon.id, 'wildlife-$areaId-0');
      expect(polygon.points, hasLength(3));
      expect(polygon.points.first.latitude, isNot(first.latitude));
      expect(polygon.points.first.longitude, isNot(first.longitude));
      expect(layer.areas.single.polygons.single.first.latitude, first.latitude);
      expect(
        layer.areas.single.polygons.single.first.longitude,
        first.longitude,
      );
    },
  );

  test('does not reserve overlays when no reviewed layer is available', () {
    expect(buildWildlifeMapPolygons(null), isEmpty);
  });
}
