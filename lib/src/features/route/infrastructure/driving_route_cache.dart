import 'dart:convert';
import 'dart:math' as math;

import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DrivingRouteCache {
  Future<DrivingRoute?> readMatching(DrivingRouteRequest request);
  Future<void> write(DrivingRouteRequest request, DrivingRoute route);
  Future<void> clear();
}

class PersistentDrivingRouteCache implements DrivingRouteCache {
  PersistentDrivingRouteCache(
    this._preferences, {
    this.storageKey = 'driving_route_cache_v1',
    this.maximumAge = const Duration(hours: 24),
    this.maximumOriginDistanceMeters = 2000,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final SharedPreferencesAsync _preferences;
  final String storageKey;
  final Duration maximumAge;
  final double maximumOriginDistanceMeters;
  final DateTime Function() now;

  @override
  Future<DrivingRoute?> readMatching(DrivingRouteRequest request) async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw);
      if (body is! Map || body['version'] != 1) return null;
      final savedAt = DateTime.tryParse('${body['savedAt'] ?? ''}')?.toUtc();
      final savedRequest = _decodeRequest(body['request']);
      final route = _decodeRoute(body['route']);
      if (savedAt == null || savedRequest == null || route == null) return null;
      final age = now().toUtc().difference(savedAt);
      if (age < Duration.zero || age > maximumAge) return null;
      if (_distanceMeters(savedRequest.origin, request.origin) >
          maximumOriginDistanceMeters) {
        return null;
      }
      if (_distanceMeters(savedRequest.destination, request.destination) >
              100 ||
          savedRequest.destinationName != request.destinationName ||
          savedRequest.travelMode != request.travelMode) {
        return null;
      }
      return route.asStale(savedAt);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(DrivingRouteRequest request, DrivingRoute route) {
    final savedAt = now().toUtc();
    return _preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'savedAt': savedAt.toIso8601String(),
        'request': _encodeRequest(request),
        'route': _encodeRoute(route),
      }),
    );
  }

  @override
  Future<void> clear() => _preferences.remove(storageKey);

  Map<String, Object?> _encodeRequest(DrivingRouteRequest request) => {
    'origin': _encodePoint(request.origin),
    'destination': _encodePoint(request.destination),
    'destinationName': request.destinationName,
    'travelMode': request.travelMode.name,
  };

  DrivingRouteRequest? _decodeRequest(Object? raw) {
    if (raw is! Map) return null;
    final origin = _decodePoint(raw['origin']);
    final destination = _decodePoint(raw['destination']);
    final name = raw['destinationName'];
    final travelMode = _travelMode(raw['travelMode']);
    if (origin == null || destination == null || name is! String) return null;
    return DrivingRouteRequest(
      origin: origin,
      destination: destination,
      destinationName: name,
      travelMode: travelMode,
    );
  }

  Map<String, Object?> _encodeRoute(DrivingRoute route) => {
    'destinationName': route.destinationName,
    'distanceMeters': route.distanceMeters,
    'durationSeconds': route.durationSeconds,
    'tollsYuan': route.tollsYuan,
    'polyline': route.polyline.map(_encodePoint).toList(),
    'polylineSegmentBreakIndexes': route.polylineSegmentBreakIndexes,
    'instructions': route.instructions,
    'travelMode': route.travelMode.name,
    'ascentMeters': route.ascentMeters,
    'descentMeters': route.descentMeters,
    'elevationSource': route.elevationSource,
    'source': route.source.name,
    'sourceId': route.sourceId,
    'durationEstimated': route.durationEstimated,
  };

  DrivingRoute? _decodeRoute(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['destinationName'];
    final distance = raw['distanceMeters'];
    final duration = raw['durationSeconds'];
    final tolls = raw['tollsYuan'];
    final travelMode = _travelMode(raw['travelMode']);
    if (name is! String ||
        distance is! int ||
        duration is! int ||
        tolls is! num) {
      return null;
    }
    final polyline = raw['polyline'] is List
        ? (raw['polyline'] as List)
              .map(_decodePoint)
              .whereType<GeoPoint>()
              .toList(growable: false)
        : const <GeoPoint>[];
    final instructions = raw['instructions'] is List
        ? (raw['instructions'] as List).whereType<String>().toList(
            growable: false,
          )
        : const <String>[];
    return DrivingRoute(
      destinationName: name,
      distanceMeters: distance,
      durationSeconds: duration,
      tollsYuan: tolls.toDouble(),
      polyline: polyline,
      polylineSegmentBreakIndexes: raw['polylineSegmentBreakIndexes'] is List
          ? (raw['polylineSegmentBreakIndexes'] as List)
                .whereType<int>()
                .where((index) => index > 0 && index < polyline.length)
                .toList(growable: false)
          : const [],
      instructions: instructions,
      travelMode: travelMode,
      ascentMeters: raw['ascentMeters'] is int
          ? raw['ascentMeters'] as int
          : null,
      descentMeters: raw['descentMeters'] is int
          ? raw['descentMeters'] as int
          : null,
      elevationSource: raw['elevationSource'] is String
          ? raw['elevationSource'] as String
          : null,
      source:
          RouteSource.values
              .where((source) => source.name == raw['source'])
              .firstOrNull ??
          RouteSource.amap,
      sourceId: raw['sourceId'] is String ? raw['sourceId'] as String : null,
      durationEstimated: raw['durationEstimated'] == true,
    );
  }

  RouteTravelMode _travelMode(Object? raw) {
    return RouteTravelMode.values
            .where((mode) => mode.name == raw)
            .firstOrNull ??
        RouteTravelMode.driving;
  }

  Map<String, Object?> _encodePoint(GeoPoint point) => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    'coordinateSystem': point.coordinateSystem.name,
  };

  GeoPoint? _decodePoint(Object? raw) {
    if (raw is! Map || raw['latitude'] is! num || raw['longitude'] is! num) {
      return null;
    }
    final systemName = raw['coordinateSystem'];
    final system = CoordinateSystem.values.where(
      (value) => value.name == systemName,
    );
    if (system.isEmpty) return null;
    return GeoPoint(
      latitude: (raw['latitude'] as num).toDouble(),
      longitude: (raw['longitude'] as num).toDouble(),
      coordinateSystem: system.first,
    ).validate();
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
