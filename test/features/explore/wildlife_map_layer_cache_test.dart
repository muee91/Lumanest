import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_cache.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 7, 16, 8);

  setUp(() => database = AppDatabase.inMemory());
  tearDown(() => database.close());

  test('round-trips a bounded layer and marks it as offline cache', () async {
    final cache = DriftWildlifeMapLayerCache(database, now: () => now);
    const center = GeoPoint(latitude: 30.25, longitude: 120.15);

    await cache.write(center: center, layer: _layer(now));
    final restored = await cache.readMatching(
      center: center,
      radiusKilometers: 20,
    );

    expect(restored?.areas.single.name, '历史观察区域');
    expect(restored?.isOfflineCache, isTrue);
    expect(restored?.cachedAt, now);
    expect(restored?.areas.single.polygons.single.first.latitude, 30);
  });

  test(
    'does not return expired, far-away or radius-mismatched layers',
    () async {
      final cache = DriftWildlifeMapLayerCache(database, now: () => now);
      const center = GeoPoint(latitude: 30.25, longitude: 120.15);
      await cache.write(center: center, layer: _layer(now));

      final expired = DriftWildlifeMapLayerCache(
        database,
        now: () => now.add(const Duration(hours: 25)),
      );
      expect(
        await expired.readMatching(center: center, radiusKilometers: 20),
        isNull,
      );
      expect(
        await cache.readMatching(
          center: const GeoPoint(latitude: 31, longitude: 121),
          radiusKilometers: 20,
        ),
        isNull,
      );
      expect(
        await cache.readMatching(center: center, radiusKilometers: 30),
        isNull,
      );
    },
  );

  test(
    'online empty result replaces old areas and clear removes all rows',
    () async {
      var clock = now;
      final cache = DriftWildlifeMapLayerCache(database, now: () => clock);
      const center = GeoPoint(latitude: 30.25, longitude: 120.15);
      await cache.write(center: center, layer: _layer(now));
      clock = now.add(const Duration(minutes: 1));
      await cache.write(
        center: center,
        layer: WildlifeMapLayer(generatedAt: clock, radiusKilometers: 20),
      );

      final restored = await cache.readMatching(
        center: center,
        radiusKilometers: 20,
      );
      expect(restored?.areas, isEmpty);

      await cache.clear();
      expect(
        await database.select(database.wildlifeMapLayerCaches).get(),
        isEmpty,
      );
    },
  );

  test('keeps only the eight most recently written locations', () async {
    var clock = now;
    final cache = DriftWildlifeMapLayerCache(database, now: () => clock);
    for (var index = 0; index < 10; index += 1) {
      await cache.write(
        center: GeoPoint(latitude: 20 + index.toDouble(), longitude: 120),
        layer: _layer(clock),
      );
      clock = clock.add(const Duration(minutes: 1));
    }

    final rows = await database.select(database.wildlifeMapLayerCaches).get();
    expect(rows, hasLength(8));
    expect(rows.map((row) => row.centerLatitude), isNot(contains(20)));
    expect(rows.map((row) => row.centerLatitude), isNot(contains(21)));
  });
}

WildlifeMapLayer _layer(DateTime generatedAt) => WildlifeMapLayer(
  generatedAt: generatedAt,
  radiusKilometers: 20,
  areas: [
    WildlifeMapArea(
      id: List.filled(64, 'a').join(),
      name: '历史观察区域',
      polygons: const [
        [
          GeoPoint(latitude: 30, longitude: 120),
          GeoPoint(latitude: 30, longitude: 120.2),
          GeoPoint(latitude: 30.2, longitude: 120.2),
          GeoPoint(latitude: 30, longitude: 120),
        ],
      ],
      source: const WildlifeMapAreaSource(
        attribution: 'Reviewed fixture',
        version: '2026.07',
      ),
    ),
  ],
);
