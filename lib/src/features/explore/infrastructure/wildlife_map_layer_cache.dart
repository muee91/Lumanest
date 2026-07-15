import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_codec.dart';

abstract interface class WildlifeMapLayerCache {
  Future<WildlifeMapLayer?> readMatching({
    required GeoPoint center,
    required int radiusKilometers,
  });

  Future<void> write({
    required GeoPoint center,
    required WildlifeMapLayer layer,
  });

  Future<void> clear();
}

class DriftWildlifeMapLayerCache implements WildlifeMapLayerCache {
  DriftWildlifeMapLayerCache(
    this._database, {
    this.maximumAge = const Duration(hours: 24),
    this.maximumCenterDistanceMeters = 5000,
    this.maximumEntries = 8,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final AppDatabase _database;
  final Duration maximumAge;
  final double maximumCenterDistanceMeters;
  final int maximumEntries;
  final DateTime Function() now;

  @override
  Future<WildlifeMapLayer?> readMatching({
    required GeoPoint center,
    required int radiusKilometers,
  }) async {
    center.validate();
    if (center.coordinateSystem != CoordinateSystem.wgs84) return null;
    final rows = await (_database.select(
      _database.wildlifeMapLayerCaches,
    )..orderBy([(table) => OrderingTerm.desc(table.savedAt)])).get();
    for (final row in rows.take(maximumEntries)) {
      if (row.radiusKilometers != radiusKilometers ||
          !_isCurrent(row.savedAt) ||
          _distanceMeters(
                GeoPoint(
                  latitude: row.centerLatitude,
                  longitude: row.centerLongitude,
                ),
                center,
              ) >
              maximumCenterDistanceMeters) {
        continue;
      }
      try {
        final decoded = jsonDecode(row.payloadJson);
        if (decoded is! Map) continue;
        return WildlifeMapLayerCodec.decode(
          Map<String, Object?>.from(decoded),
          expectedRadius: radiusKilometers,
          cachedAt: row.savedAt,
        );
      } on Object {
        continue;
      }
    }
    return null;
  }

  @override
  Future<void> write({
    required GeoPoint center,
    required WildlifeMapLayer layer,
  }) async {
    center.validate();
    if (center.coordinateSystem != CoordinateSystem.wgs84) return;
    final savedAt = now().toUtc();
    final payload = jsonEncode(WildlifeMapLayerCodec.encode(layer));
    if (payload.isEmpty || payload.length > 524288) return;
    final id = sha256
        .convert(
          utf8.encode(
            '${center.latitude.toStringAsFixed(5)}\u0000'
            '${center.longitude.toStringAsFixed(5)}\u0000'
            '${layer.radiusKilometers}',
          ),
        )
        .toString();
    await _database.transaction(() async {
      await _database
          .into(_database.wildlifeMapLayerCaches)
          .insertOnConflictUpdate(
            WildlifeMapLayerCachesCompanion.insert(
              id: id,
              centerLatitude: center.latitude,
              centerLongitude: center.longitude,
              radiusKilometers: layer.radiusKilometers,
              savedAt: savedAt,
              generatedAt: layer.generatedAt.toUtc(),
              payloadJson: payload,
            ),
          );
      final rows = await (_database.select(
        _database.wildlifeMapLayerCaches,
      )..orderBy([(table) => OrderingTerm.desc(table.savedAt)])).get();
      final expiredIds = rows
          .skip(maximumEntries)
          .map((row) => row.id)
          .toList();
      if (expiredIds.isNotEmpty) {
        await (_database.delete(
          _database.wildlifeMapLayerCaches,
        )..where((table) => table.id.isIn(expiredIds))).go();
      }
    });
  }

  @override
  Future<void> clear() =>
      _database.delete(_database.wildlifeMapLayerCaches).go();

  bool _isCurrent(DateTime savedAt) {
    final age = now().toUtc().difference(savedAt.toUtc());
    return age >= Duration.zero && age <= maximumAge;
  }

  static double _distanceMeters(GeoPoint first, GeoPoint second) {
    const radius = 6371000.0;
    final firstLatitude = first.latitude * math.pi / 180;
    final secondLatitude = second.latitude * math.pi / 180;
    final latitudeDelta = (second.latitude - first.latitude) * math.pi / 180;
    final longitudeDelta = (second.longitude - first.longitude) * math.pi / 180;
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return radius *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }
}
