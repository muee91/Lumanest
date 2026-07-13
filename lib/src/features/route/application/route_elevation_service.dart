import 'dart:math' as math;

import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/elevation_profile.dart';

class RouteElevationService {
  const RouteElevationService(this._repository);

  final ElevationProfileRepository _repository;

  Future<DrivingRoute> enrich(DrivingRoute route) async {
    if (route.travelMode != RouteTravelMode.walking ||
        route.polyline.length < 2) {
      return route;
    }
    final sampled = _sample(
      route.polyline,
      maximum: 64,
    ).map(_asWgs84).toList(growable: false);
    final profile = await _repository.fetch(sampled);
    if (profile.elevations.length != sampled.length) {
      throw const FormatException('Elevation profile length mismatch');
    }
    final smoothed = _smooth(profile.elevations);
    var ascent = 0.0;
    var descent = 0.0;
    var anchor = smoothed.first;
    for (final elevation in smoothed.skip(1)) {
      final delta = elevation - anchor;
      if (delta.abs() < 3) continue;
      if (delta > 0) {
        ascent += delta;
      } else {
        descent -= delta;
      }
      anchor = elevation;
    }
    return route.withElevation(
      ascentMeters: ascent.round(),
      descentMeters: descent.round(),
      source: profile.source,
    );
  }

  List<GeoPoint> _sample(List<GeoPoint> points, {required int maximum}) {
    if (points.length <= maximum) return List.unmodifiable(points);
    return List.generate(maximum, (index) {
      final ratio = index / (maximum - 1);
      return points[(ratio * (points.length - 1)).round()];
    }, growable: false);
  }

  GeoPoint _asWgs84(GeoPoint point) =>
      point.coordinateSystem == CoordinateSystem.gcj02
      ? ChinaCoordinateConverter.gcj02ToWgs84(point)
      : point;

  List<double> _smooth(List<double> elevations) {
    if (elevations.length < 3) return List.unmodifiable(elevations);
    return List.generate(elevations.length, (index) {
      final start = math.max(0, index - 1);
      final end = math.min(elevations.length - 1, index + 1);
      var sum = 0.0;
      for (var cursor = start; cursor <= end; cursor++) {
        sum += elevations[cursor];
      }
      return sum / (end - start + 1);
    }, growable: false);
  }
}
