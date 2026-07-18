import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/location/domain/manual_location_selection.dart';

abstract interface class ManualLocationStore {
  Future<ManualLocationSelection?> read();
  Future<void> write(ManualLocationSelection value);
  Future<void> clear();
}

class DriftManualLocationStore implements ManualLocationStore {
  DriftManualLocationStore(this._database);

  final AppDatabase _database;

  @override
  Future<ManualLocationSelection?> read() async {
    final row = await (_database.select(
      _database.manualLocations,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    if (row == null) return null;
    return ManualLocationSelection(
      name: row.name,
      address: row.address,
      selectedAt: row.selectedAt,
      location: LocationReading(
        point: GeoPoint(latitude: row.latitude, longitude: row.longitude),
        recordedAt: row.selectedAt,
        accuracyMeters: 1000,
      ),
    );
  }

  @override
  Future<void> write(ManualLocationSelection value) {
    return _database
        .into(_database.manualLocations)
        .insertOnConflictUpdate(
          ManualLocationsCompanion.insert(
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
    _database.manualLocations,
  )..where((row) => row.id.equals(1))).go();
}

final manualLocationStoreProvider = Provider<ManualLocationStore>((ref) {
  return DriftManualLocationStore(ref.watch(appDatabaseProvider));
});
