import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class RouteSupportCache {
  Future<List<RouteSupportStop>?> readMatching(DrivingRoute route);
  Future<void> write(DrivingRoute route, List<RouteSupportStop> stops);
  Future<void> clear();
}

class PersistentRouteSupportCache implements RouteSupportCache {
  PersistentRouteSupportCache(
    this._preferences, {
    this.storageKey = 'route_support_cache_v1',
    this.maximumAge = const Duration(hours: 24),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final SharedPreferencesAsync _preferences;
  final String storageKey;
  final Duration maximumAge;
  final DateTime Function() now;

  @override
  Future<List<RouteSupportStop>?> readMatching(DrivingRoute route) async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw);
      if (body is! Map ||
          body['version'] != 1 ||
          body['routeFingerprint'] != _fingerprint(route)) {
        return null;
      }
      final savedAt = DateTime.tryParse('${body['savedAt'] ?? ''}')?.toUtc();
      if (savedAt == null) return null;
      final age = now().toUtc().difference(savedAt);
      if (age < Duration.zero || age > maximumAge) return null;
      final rawStops = body['stops'];
      if (rawStops is! List || rawStops.length > 12) return null;
      final stops = rawStops
          .map((value) => _decodeStop(value, savedAt))
          .toList();
      if (stops.any((stop) => stop == null)) return null;
      return List.unmodifiable(stops.cast<RouteSupportStop>());
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(DrivingRoute route, List<RouteSupportStop> stops) {
    final savedAt = now().toUtc();
    return _preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'routeFingerprint': _fingerprint(route),
        'savedAt': savedAt.toIso8601String(),
        'stops': stops.take(12).map(_encodeStop).toList(growable: false),
      }),
    );
  }

  @override
  Future<void> clear() => _preferences.remove(storageKey);

  String _fingerprint(DrivingRoute route) {
    final geometry = route.polyline
        .map(
          (point) => [
            point.latitude,
            point.longitude,
            point.coordinateSystem.name,
          ],
        )
        .toList(growable: false);
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'mode': route.travelMode.name,
              'geometry': geometry,
              'breaks': route.polylineSegmentBreakIndexes,
            }),
          ),
        )
        .toString();
  }

  Map<String, Object?> _encodeStop(RouteSupportStop stop) => {
    'id': stop.place.id,
    'name': stop.place.name,
    'category': stop.place.category.name,
    'latitude': stop.place.point.latitude,
    'longitude': stop.place.point.longitude,
    'coordinateSystem': stop.place.point.coordinateSystem.name,
    'distanceMeters': stop.place.distanceMeters,
    'address': stop.place.address,
    'routeProgress': stop.routeProgress,
  };

  RouteSupportStop? _decodeStop(Object? raw, DateTime cachedAt) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final category = NearbyPlaceCategory.values
        .where((value) => value.name == raw['category'])
        .firstOrNull;
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    final system = CoordinateSystem.values
        .where((value) => value.name == raw['coordinateSystem'])
        .firstOrNull;
    final distance = raw['distanceMeters'];
    final address = raw['address'];
    final progress = raw['routeProgress'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 160 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 160 ||
        category == null ||
        latitude is! num ||
        longitude is! num ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        system == null ||
        system == CoordinateSystem.unknown ||
        distance is! int ||
        distance < 0 ||
        address != null && (address is! String || address.length > 300) ||
        progress is! num ||
        !progress.isFinite ||
        progress < 0 ||
        progress > 1) {
      return null;
    }
    final point = GeoPoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      coordinateSystem: system,
    ).validate();
    return RouteSupportStop(
      place: NearbyPlace(
        id: id,
        name: name,
        category: category,
        point: point,
        distanceMeters: distance,
        address: address as String?,
      ),
      routeProgress: progress.toDouble(),
      cachedAt: cachedAt,
    );
  }
}
