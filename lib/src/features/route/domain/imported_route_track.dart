import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

class ImportedRouteTrack {
  ImportedRouteTrack({
    required this.id,
    required this.name,
    required this.importedAt,
    required List<GeoPoint> points,
    List<int> segmentBreakIndexes = const [],
    required this.distanceMeters,
    required this.durationSeconds,
    required this.durationEstimated,
    this.ascentMeters,
    this.descentMeters,
  }) : points = List.unmodifiable(points),
       segmentBreakIndexes = List.unmodifiable(segmentBreakIndexes);

  final String id;
  final String name;
  final DateTime importedAt;
  final List<GeoPoint> points;
  final List<int> segmentBreakIndexes;
  final int distanceMeters;
  final int durationSeconds;
  final bool durationEstimated;
  final int? ascentMeters;
  final int? descentMeters;

  GeoPoint get destination => points.last;

  DrivingRoute toRoute() => DrivingRoute(
    destinationName: name,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    tollsYuan: 0,
    polyline: points,
    polylineSegmentBreakIndexes: segmentBreakIndexes,
    travelMode: RouteTravelMode.walking,
    ascentMeters: ascentMeters,
    descentMeters: descentMeters,
    elevationSource: ascentMeters == null ? null : 'GPX 轨迹记录',
    source: RouteSource.importedGpx,
    sourceId: id,
    durationEstimated: durationEstimated,
  );
}
