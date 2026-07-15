import 'dart:convert';

import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocationSearchCache {
  Future<List<LocationSearchResult>?> readMatching(String keywords);
  Future<void> write(String keywords, List<LocationSearchResult> results);
  Future<void> clear();
}

class PersistentLocationSearchCache implements LocationSearchCache {
  PersistentLocationSearchCache(
    this._preferences, {
    this.storageKey = 'location_search_cache_v1',
    this.maximumAge = const Duration(hours: 24),
    this.maximumEntries = 10,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final SharedPreferencesAsync _preferences;
  final String storageKey;
  final Duration maximumAge;
  final int maximumEntries;
  final DateTime Function() now;
  Future<void> _writeQueue = Future.value();

  @override
  Future<List<LocationSearchResult>?> readMatching(String keywords) async {
    final query = _normalize(keywords);
    if (query.isEmpty) return null;
    final entries = await _readEntries();
    for (final entry in entries) {
      if (entry['query'] != query) continue;
      final savedAt = DateTime.tryParse('${entry['savedAt'] ?? ''}')?.toUtc();
      if (savedAt == null || !_isCurrent(savedAt)) return null;
      final rawResults = entry['results'];
      if (rawResults is! List || rawResults.isEmpty || rawResults.length > 10) {
        return null;
      }
      try {
        final decoded = rawResults
            .map((raw) => _decodeResult(raw, savedAt))
            .toList(growable: false);
        if (decoded.any((result) => result == null)) return null;
        return List.unmodifiable(decoded.cast<LocationSearchResult>());
      } on Object {
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> write(String keywords, List<LocationSearchResult> results) {
    final query = _normalize(keywords);
    if (query.isEmpty || query.length > 200 || results.isEmpty) {
      return Future.value();
    }
    final encodedResults = results.take(10).map(_encodeResult).toList();
    final operation = _writeQueue.then((_) async {
      final entries = await _readEntries();
      entries.removeWhere((entry) => entry['query'] == query);
      entries.insert(0, {
        'query': query,
        'savedAt': now().toUtc().toIso8601String(),
        'results': encodedResults,
      });
      await _preferences.setString(
        storageKey,
        jsonEncode({
          'version': 1,
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
      if (body is! Map || body['version'] != 1 || body['entries'] is! List) {
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

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static Map<String, Object?> _encodeResult(LocationSearchResult result) => {
    'id': result.id,
    'name': result.name,
    'latitude': result.point.latitude,
    'longitude': result.point.longitude,
    'coordinateSystem': result.point.coordinateSystem.name,
    'address': result.address,
  };

  static LocationSearchResult? _decodeResult(Object? raw, DateTime savedAt) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    final address = raw['address'];
    final system = CoordinateSystem.values
        .where((value) => value.name == raw['coordinateSystem'])
        .firstOrNull;
    if (id is! String ||
        id.isEmpty ||
        id.length > 160 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 160 ||
        latitude is! num ||
        !latitude.isFinite ||
        longitude is! num ||
        !longitude.isFinite ||
        system == null ||
        address != null && (address is! String || address.length > 300)) {
      return null;
    }
    return LocationSearchResult(
      id: id,
      name: name,
      point: GeoPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        coordinateSystem: system,
      ).validate(),
      address: address as String?,
      cachedAt: savedAt,
    );
  }
}
