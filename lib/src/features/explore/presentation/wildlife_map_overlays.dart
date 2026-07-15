import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:x_amap_base/x_amap_base.dart';

Set<Polygon> buildWildlifeMapPolygons(WildlifeMapLayer? layer) {
  if (layer == null) return const <Polygon>{};
  final overlays = <Polygon>{};
  for (final area in layer.areas) {
    for (var index = 0; index < area.polygons.length; index += 1) {
      final ring = area.polygons[index];
      final points = ring
          .take(ring.length - 1)
          .map(ChinaCoordinateConverter.wgs84ToGcj02)
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false);
      if (points.length < 3) continue;
      final polygon = Polygon(
        points: points,
        strokeWidth: 2,
        strokeColor: const Color(0xCC247A5A),
        fillColor: const Color(0x332C9B72),
      );
      polygon.setIdForCopy('wildlife-${area.id}-$index');
      overlays.add(polygon);
    }
  }
  return overlays;
}
