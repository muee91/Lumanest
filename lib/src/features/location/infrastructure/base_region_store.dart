import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/location/domain/base_region.dart';

abstract interface class BaseRegionStore {
  Future<BaseRegion?> read();
  Future<void> write(BaseRegion value);
  Future<void> clear();
}

class DriftBaseRegionStore implements BaseRegionStore {
  DriftBaseRegionStore(this._database);

  final AppDatabase _database;

  @override
  Future<BaseRegion?> read() async {
    final row = await (_database.select(
      _database.baseRegions,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    if (row == null) return null;
    return BaseRegion(
      name: row.name,
      address: row.address,
      location: LocationReading(
        point: GeoPoint(latitude: row.latitude, longitude: row.longitude),
        recordedAt: row.selectedAt,
        accuracyMeters: 1000,
      ),
      selectedAt: row.selectedAt,
    );
  }

  @override
  Future<void> write(BaseRegion value) {
    return _database
        .into(_database.baseRegions)
        .insertOnConflictUpdate(
          BaseRegionsCompanion.insert(
            id: const Value(1),
            name: value.name,
            address: Value(value.address),
            latitude: value.location.point.latitude,
            longitude: value.location.point.longitude,
            selectedAt: value.selectedAt.toUtc(),
          ),
        );
  }

  @override
  Future<void> clear() => (_database.delete(
    _database.baseRegions,
  )..where((row) => row.id.equals(1))).go();
}

final baseRegionStoreProvider = Provider<BaseRegionStore>((ref) {
  return DriftBaseRegionStore(ref.watch(appDatabaseProvider));
});
