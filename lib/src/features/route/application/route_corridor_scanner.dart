import 'dart:math' as math;

import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';

class RouteCorridorScanner {
  const RouteCorridorScanner(this._places);

  final NearbyPlaceRepository _places;

  Future<List<RouteSupportStop>> scan(DrivingRoute route) async {
    final samples = _sample(route, maximum: 3);
    if (samples.isEmpty) return const [];
    final categories = route.travelMode == RouteTravelMode.walking
        ? const [NearbyPlaceCategory.food, NearbyPlaceCategory.supply]
        : const [
            NearbyPlaceCategory.fuel,
            NearbyPlaceCategory.food,
            NearbyPlaceCategory.supply,
          ];
    final attempts = await Future.wait([
      for (final sample in samples)
        for (final category in categories) _fetch(sample, category),
    ]);
    final successful = attempts
        .where((attempt) => attempt.error == null)
        .toList(growable: false);
    if (successful.isEmpty) {
      final failed = attempts.first;
      Error.throwWithStackTrace(failed.error!, failed.stackTrace!);
    }

    final unique = <String, RouteSupportStop>{};
    for (final attempt in successful) {
      for (final place in attempt.places) {
        final stop = RouteSupportStop(
          place: place,
          routeProgress: attempt.sample.progress,
        );
        final existing = unique[place.id];
        if (existing == null ||
            place.distanceMeters < existing.place.distanceMeters) {
          unique[place.id] = stop;
        }
      }
    }
    final result = unique.values.toList(growable: false);
    result.sort((a, b) {
      final progressOrder = a.routeProgress.compareTo(b.routeProgress);
      if (progressOrder != 0) return progressOrder;
      final distanceOrder = a.place.distanceMeters.compareTo(
        b.place.distanceMeters,
      );
      return distanceOrder != 0
          ? distanceOrder
          : a.place.category.index.compareTo(b.place.category.index);
    });
    return List.unmodifiable(result.take(12));
  }

  Future<_ScanAttempt> _fetch(
    _RouteSample sample,
    NearbyPlaceCategory category,
  ) async {
    try {
      final places = await _places.fetchNearby(
        center: sample.point,
        category: category,
        radiusMeters: 5000,
      );
      final nearest = places.toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      return _ScanAttempt.success(
        sample,
        nearest.take(1).toList(growable: false),
      );
    } on Object catch (error, stackTrace) {
      return _ScanAttempt.failure(sample, error, stackTrace);
    }
  }

  List<_RouteSample> _sample(DrivingRoute route, {required int maximum}) {
    final points = route.polyline;
    if (points.isEmpty) return const [];
    final breaks = route.polylineSegmentBreakIndexes.toSet();
    final cumulative = List<double>.filled(points.length, 0);
    for (var index = 1; index < points.length; index++) {
      cumulative[index] = cumulative[index - 1];
      if (!breaks.contains(index)) {
        cumulative[index] += _distanceMeters(points[index - 1], points[index]);
      }
    }
    final total = cumulative.last;
    double progressAt(int index) => total > 0
        ? (cumulative[index] / total).clamp(0, 1)
        : points.length == 1
        ? 0
        : index / (points.length - 1);
    if (points.length <= maximum) {
      return List.generate(
        points.length,
        (index) => _RouteSample(points[index], progressAt(index)),
        growable: false,
      );
    }

    final indexes = <int>{};
    for (var sampleIndex = 0; sampleIndex < maximum; sampleIndex++) {
      final target = sampleIndex / (maximum - 1);
      var bestIndex = 0;
      var bestDelta = double.infinity;
      for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
        final delta = (progressAt(pointIndex) - target).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          bestIndex = pointIndex;
        }
      }
      indexes.add(bestIndex);
    }
    final sorted = indexes.toList()..sort();
    return sorted
        .map((index) => _RouteSample(points[index], progressAt(index)))
        .toList(growable: false);
  }

  double _distanceMeters(GeoPoint first, GeoPoint second) {
    const earthRadius = 6371000.0;
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
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _RouteSample {
  const _RouteSample(this.point, this.progress);

  final GeoPoint point;
  final double progress;
}

class _ScanAttempt {
  const _ScanAttempt._({
    required this.sample,
    required this.places,
    this.error,
    this.stackTrace,
  });

  factory _ScanAttempt.success(_RouteSample sample, List<NearbyPlace> places) =>
      _ScanAttempt._(sample: sample, places: places);

  factory _ScanAttempt.failure(
    _RouteSample sample,
    Object error,
    StackTrace stackTrace,
  ) => _ScanAttempt._(
    sample: sample,
    places: const [],
    error: error,
    stackTrace: stackTrace,
  );

  final _RouteSample sample;
  final List<NearbyPlace> places;
  final Object? error;
  final StackTrace? stackTrace;
}
