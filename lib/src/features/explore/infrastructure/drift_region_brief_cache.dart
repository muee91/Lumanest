import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_region_brief_repository.dart';

class RegionBriefCacheKey {
  const RegionBriefCacheKey({
    required this.regionKey,
    required this.locale,
    this.profileVersion = '2',
  });

  final String regionKey;
  final String locale;
  final String profileVersion;

  factory RegionBriefCacheKey.forPoint(
    GeoPoint point, {
    required String locale,
  }) {
    final latitudeCell = (point.latitude / .05).floor();
    final longitudeCell = (point.longitude / .05).floor();
    return RegionBriefCacheKey(
      regionKey: 'g$latitudeCell:$longitudeCell',
      locale: locale,
    );
  }
}

abstract interface class RegionBriefLocalCache {
  Future<RegionBrief?> read(RegionBriefCacheKey key);
  Future<void> write(RegionBriefCacheKey key, RegionBrief brief);
  Future<void> clear();
}

class DriftRegionBriefCache implements RegionBriefLocalCache {
  DriftRegionBriefCache(this._database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;

  @override
  Future<RegionBrief?> read(RegionBriefCacheKey key) async {
    final row =
        await (_database.select(_database.regionBriefCaches)..where(
              (table) =>
                  table.regionKey.equals(key.regionKey) &
                  table.locale.equals(key.locale) &
                  table.profileVersion.equals(key.profileVersion),
            ))
            .getSingleOrNull();
    if (row == null || !row.expiresAt.isAfter(_now().toUtc())) return null;
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) return null;
      final brief = RegionBriefCodec.parse(Map<String, Object?>.from(decoded));
      if (brief.regionId != key.regionKey) return null;
      await (_database.update(_database.regionBriefCaches)..where(
            (table) =>
                table.regionKey.equals(key.regionKey) &
                table.locale.equals(key.locale) &
                table.profileVersion.equals(key.profileVersion),
          ))
          .write(
            RegionBriefCachesCompanion(lastAccessedAt: Value(_now().toUtc())),
          );
      return brief;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(RegionBriefCacheKey key, RegionBrief brief) async {
    if (brief.regionId != key.regionKey) return;
    final generatedAt = brief.generatedAt.toUtc();
    final expiresAt = brief.expiresAt.toUtc();
    await _database
        .into(_database.regionBriefCaches)
        .insertOnConflictUpdate(
          RegionBriefCachesCompanion.insert(
            regionKey: key.regionKey,
            locale: key.locale,
            profileVersion: key.profileVersion,
            payloadJson: jsonEncode(RegionBriefCodec.encode(brief)),
            generatedAt: generatedAt,
            expiresAt: expiresAt,
            stableExpiresAt: expiresAt,
            completeness: brief.completeness.name,
            lastAccessedAt: _now().toUtc(),
          ),
        );
  }

  @override
  Future<void> clear() => _database.delete(_database.regionBriefCaches).go();
}
