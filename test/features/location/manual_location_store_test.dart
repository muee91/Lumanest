import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/location/domain/manual_location_selection.dart';
import 'package:luma_nest/src/features/location/infrastructure/manual_location_store.dart';

void main() {
  test(
    'manual location survives a new store instance and clears locally',
    () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final selectedAt = DateTime.utc(2026, 7, 17, 8);
      final first = DriftManualLocationStore(database);
      await first.write(
        ManualLocationSelection(
          name: '杭州西湖风景名胜区',
          address: '龙井路1号',
          selectedAt: selectedAt,
          location: LocationReading(
            point: const GeoPoint(latitude: 30.243, longitude: 120.15),
            recordedAt: selectedAt,
            accuracyMeters: 1000,
          ),
        ),
      );

      final restored = await DriftManualLocationStore(database).read();
      expect(restored?.name, '杭州西湖风景名胜区');
      expect(restored?.location.point.latitude, 30.243);

      await first.clear();
      expect(await DriftManualLocationStore(database).read(), isNull);
    },
  );
}
