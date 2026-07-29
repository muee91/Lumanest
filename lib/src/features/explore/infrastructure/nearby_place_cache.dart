import 'dart:convert';
import 'dart:math' as math;

import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class NearbyPlaceCache {
  Future<List<NearbyPlace>?> readMatching({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    required int radiusMeters,
  });
  Future<void> write({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    required int radiusMeters,
    required List<NearbyPlace> places,
  });
  Future<void> clear();
}

class PersistentNearbyPlaceCache implements NearbyPlaceCache {
  PersistentNearbyPlaceCache(
    this._preferences, {
    this.storageKey = 'nearby_place_cache_v7',
    this.maximumAge = const Duration(hours: 24),
    this.maximumCenterDistanceMeters = 500,
    this.maximumEntries = 16,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final SharedPreferencesAsync _preferences;
  final String storageKey;
  final Duration maximumAge;
  final double maximumCenterDistanceMeters;
  final int maximumEntries;
  final DateTime Function() now;
  Future<void> _writeQueue = Future.value();

  @override
  Future<List<NearbyPlace>?> readMatching({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    required int radiusMeters,
  }) async {
    final entries = await _readEntries();
    for (final entry in entries) {
      if (entry['category'] != category.name ||
          entry['radiusMeters'] != radiusMeters) {
        continue;
      }
      final savedAt = DateTime.tryParse('${entry['savedAt'] ?? ''}')?.toUtc();
      final savedCenter = _decodePoint(entry['center']);
      if (savedAt == null ||
          savedCenter == null ||
          !_isCurrent(savedAt) ||
          _distanceMeters(savedCenter, center) > maximumCenterDistanceMeters) {
        continue;
      }
      final rawPlaces = entry['places'];
      if (rawPlaces is! List || rawPlaces.isEmpty || rawPlaces.length > 80) {
        return null;
      }
      try {
        final decoded = rawPlaces
            .map((raw) => _decodePlace(raw, savedAt))
            .toList(growable: false);
        if (decoded.any((place) => place == null)) return null;
        return List.unmodifiable(decoded.cast<NearbyPlace>());
      } on Object {
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> write({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    required int radiusMeters,
    required List<NearbyPlace> places,
  }) {
    if (places.isEmpty || radiusMeters < 100 || radiusMeters > 50000) {
      return Future.value();
    }
    center.validate();
    final encodedPlaces = places.take(80).map(_encodePlace).toList();
    final operation = _writeQueue.then((_) async {
      final entries = await _readEntries();
      entries.removeWhere((entry) {
        if (entry['category'] != category.name ||
            entry['radiusMeters'] != radiusMeters) {
          return false;
        }
        final previousCenter = _decodePoint(entry['center']);
        return previousCenter != null &&
            _distanceMeters(previousCenter, center) <=
                maximumCenterDistanceMeters;
      });
      entries.insert(0, {
        'category': category.name,
        'radiusMeters': radiusMeters,
        'center': _encodePoint(center),
        'savedAt': now().toUtc().toIso8601String(),
        'places': encodedPlaces,
      });
      await _preferences.setString(
        storageKey,
        jsonEncode({
          'version': 7,
          'entries': entries.take(maximumEntries).toList(growable: false),
        }),
      );
    });
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  @override
  Future<void> clear() {
    final operation = _writeQueue.then((_) => _preferences.remove(storageKey));
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<List<Map<String, Object?>>> _readEntries() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return [];
    try {
      final body = jsonDecode(raw);
      if (body is! Map || body['version'] != 7 || body['entries'] is! List) {
        return [];
      }
      return (body['entries'] as List)
          .whereType<Map>()
          .map((entry) => Map<String, Object?>.from(entry))
          .take(maximumEntries)
          .toList();
    } on Object {
      return [];
    }
  }

  bool _isCurrent(DateTime savedAt) {
    final age = now().toUtc().difference(savedAt);
    return age >= Duration.zero && age <= maximumAge;
  }

  static Map<String, Object?> _encodePoint(GeoPoint point) => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    'coordinateSystem': point.coordinateSystem.name,
  };

  static GeoPoint? _decodePoint(Object? raw) {
    if (raw is! Map) return null;
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    final system = CoordinateSystem.values
        .where((value) => value.name == raw['coordinateSystem'])
        .firstOrNull;
    if (latitude is! num ||
        !latitude.isFinite ||
        longitude is! num ||
        !longitude.isFinite ||
        system == null) {
      return null;
    }
    return GeoPoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      coordinateSystem: system,
    ).validate();
  }

  static Map<String, Object?> _encodePlace(NearbyPlace place) => {
    'id': place.id,
    'name': place.name,
    'category': place.category.name,
    'point': _encodePoint(place.point),
    'distanceMeters': place.distanceMeters,
    'address': place.address,
    'provinceName': place.provinceName,
    'cityName': place.cityName,
    'districtName': place.districtName,
    'matchedKeyword': place.matchedKeyword,
    'administrativeRelation': place.administrativeRelation.name,
    'drivingDurationSeconds': place.drivingDurationSeconds,
    'drivingDistanceMeters': place.drivingDistanceMeters,
    'sourceEvidenceCount': place.sourceEvidenceCount,
    'aiDiscovered': place.aiDiscovered,
    // POI-attached provider images cannot prove that the pictured subject is
    // this place. Verified media is resolved on demand and never persisted in
    // the nearby-place cache.
    'media': const [],
  };

  static NearbyPlace? _decodePlace(Object? raw, DateTime savedAt) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final category = NearbyPlaceCategory.values
        .where((value) => value.name == raw['category'])
        .firstOrNull;
    final point = _decodePoint(raw['point']);
    final distance = raw['distanceMeters'];
    final address = raw['address'];
    final relation = NearbyAdministrativeRelation.values
        .where((value) => value.name == raw['administrativeRelation'])
        .firstOrNull;
    final drivingDuration = raw['drivingDurationSeconds'];
    final drivingDistance = raw['drivingDistanceMeters'];
    final sourceEvidenceCount = raw['sourceEvidenceCount'];
    final aiDiscovered = raw['aiDiscovered'];
    final rawMedia = raw['media'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 160 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 160 ||
        category == null ||
        point == null ||
        distance is! int ||
        distance < 0 ||
        relation == null ||
        drivingDuration != null &&
            (drivingDuration is! int || drivingDuration < 0) ||
        drivingDistance != null &&
            (drivingDistance is! int || drivingDistance < 0) ||
        sourceEvidenceCount is! int ||
        sourceEvidenceCount < 0 ||
        aiDiscovered is! bool ||
        rawMedia is! List ||
        rawMedia.length > 3 ||
        address != null && (address is! String || address.length > 300)) {
      return null;
    }
    return NearbyPlace(
      id: id,
      name: name,
      category: category,
      point: point,
      distanceMeters: distance,
      address: address as String?,
      provinceName: raw['provinceName'] as String?,
      cityName: raw['cityName'] as String?,
      districtName: raw['districtName'] as String?,
      matchedKeyword: raw['matchedKeyword'] as String?,
      administrativeRelation: relation,
      drivingDurationSeconds: drivingDuration as int?,
      drivingDistanceMeters: drivingDistance as int?,
      sourceEvidenceCount: sourceEvidenceCount,
      aiDiscovered: aiDiscovered,
      media: const [],
      cachedAt: savedAt,
    );
  }

  static double _distanceMeters(GeoPoint first, GeoPoint second) {
    final a = first.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(first)
        : first;
    final b = second.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(second)
        : second;
    const radius = 6371000.0;
    final firstLat = a.latitude * math.pi / 180;
    final secondLat = b.latitude * math.pi / 180;
    final latitudeDelta = (b.latitude - a.latitude) * math.pi / 180;
    final longitudeDelta = (b.longitude - a.longitude) * math.pi / 180;
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLat) *
            math.cos(secondLat) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return radius *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }
}
