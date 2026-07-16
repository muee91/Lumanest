import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

/// Bounded transient route context. It is not written to disk or cache.
class RouteCorridorSample {
  RouteCorridorSample({
    required this.point,
    required this.expectedAt,
    required this.progress,
  }) : assert(point.coordinateSystem == CoordinateSystem.wgs84),
       assert(progress >= 0 && progress <= 1);

  final GeoPoint point;
  final DateTime expectedAt;
  final double progress;

  Map<String, Object?> toRequest() => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    'system': 'wgs84',
    'expectedAt': expectedAt.toUtc().toIso8601String(),
    'progress': progress,
  };
}

class RouteCorridorContext {
  RouteCorridorContext({
    required this.routeId,
    required Iterable<RouteCorridorSample> samples,
  }) : samples = List.unmodifiable(samples) {
    if (routeId.isEmpty || routeId.length > 160 || this.samples.length > 3) {
      throw ArgumentError('invalid transient route corridor');
    }
  }

  final String routeId;
  final List<RouteCorridorSample> samples;

  bool get isUsable => samples.isNotEmpty;

  Map<String, Object?> toRequest() => {
    'routeId': routeId,
    'corridorSamples': samples
        .map((sample) => sample.toRequest())
        .toList(growable: false),
  };

  /// Geometry-only samples with estimates based on the route duration.
  factory RouteCorridorContext.fromPolyline({
    required List<GeoPoint> polyline,
    required int durationSeconds,
    required DateTime departureAt,
    required String routeSeed,
  }) {
    if (polyline.length < 2 || durationSeconds < 1) {
      throw ArgumentError(
        'a loaded route with duration and at least two points is required',
      );
    }
    final samples = _sampleIndexes(polyline).map((entry) {
      final point = polyline[entry.index];
      final wgs84 = point.coordinateSystem == CoordinateSystem.gcj02
          ? ChinaCoordinateConverter.gcj02ToWgs84(point)
          : point;
      return RouteCorridorSample(
        point: wgs84,
        expectedAt: departureAt.toUtc().add(
          Duration(seconds: (durationSeconds * entry.progress).round()),
        ),
        progress: double.parse(entry.progress.toStringAsFixed(6)),
      );
    });
    final fingerprintInput = StringBuffer(routeSeed)
      ..write(':')
      ..write(durationSeconds)
      ..write(':')
      ..write(polyline.length);
    return RouteCorridorContext(
      // ignore: prefer_interpolation_to_compose_strings
      routeId: 'r' + _opaqueHash(fingerprintInput.toString()),
      samples: samples,
    );
  }

  static List<_RouteProgress> _sampleIndexes(List<GeoPoint> points) {
    final cumulative = <double>[0];
    for (var index = 1; index < points.length; index += 1) {
      cumulative.add(
        cumulative.last + _distance(points[index - 1], points[index]),
      );
    }
    final total = cumulative.last;
    double progress(int index) =>
        total > 0 ? cumulative[index] / total : index / (points.length - 1);
    const maximum = 3;
    if (points.length <= maximum) {
      return List.generate(
        points.length,
        (index) => _RouteProgress(index, progress(index)),
        growable: false,
      );
    }
    final selected = <int>{};
    for (var sample = 0; sample < maximum; sample += 1) {
      final desired = sample / (maximum - 1);
      var best = 0;
      var delta = double.infinity;
      for (var index = 0; index < points.length; index += 1) {
        final currentDelta = (progress(index) - desired).abs();
        if (currentDelta < delta) {
          best = index;
          delta = currentDelta;
        }
      }
      selected.add(best);
    }
    final indexes = selected.toList()..sort();
    return indexes
        .map((index) => _RouteProgress(index, progress(index)))
        .toList(growable: false);
  }

  static double _distance(GeoPoint first, GeoPoint second) {
    const radius = 6371000.0;
    final lat1 = first.latitude * math.pi / 180;
    final lat2 = second.latitude * math.pi / 180;
    final deltaLat = (second.latitude - first.latitude) * math.pi / 180;
    final deltaLon = (second.longitude - first.longitude) * math.pi / 180;
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static String _opaqueHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _RouteProgress {
  const _RouteProgress(this.index, this.progress);

  final int index;
  final double progress;
}

class RouteCorridorContextController extends Notifier<RouteCorridorContext?> {
  @override
  RouteCorridorContext? build() {
    ref.listen<RouteContextState>(routeContextStateProvider, (_, next) {
      if (!next.hasRoute) state = null;
    });
    return null;
  }

  void replace(RouteCorridorContext context) => state = context;

  void clear() => state = null;
}

final routeCorridorContextProvider =
    NotifierProvider<RouteCorridorContextController, RouteCorridorContext?>(
      RouteCorridorContextController.new,
    );
