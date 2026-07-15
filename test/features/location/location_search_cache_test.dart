import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/location_search_cache.dart';
import 'package:luma_nest/src/features/location/infrastructure/resilient_location_search_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 8);
  const onlineResults = [
    LocationSearchResult(
      id: 'west-lake',
      name: '西湖风景名胜区',
      point: GeoPoint(
        latitude: 30.231,
        longitude: 120.132,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
      address: '杭州市西湖区',
    ),
  ];

  test('round-trips a normalized query as explicit offline data', () async {
    final cache = PersistentLocationSearchCache(
      SharedPreferencesAsync(),
      storageKey: 'location-search-roundtrip',
      now: () => now,
    );
    await cache.write('  西湖  景区 ', onlineResults);

    final restored = await cache.readMatching('西湖 景区');

    expect(restored?.single.name, '西湖风景名胜区');
    expect(restored?.single.point.coordinateSystem, CoordinateSystem.gcj02);
    expect(restored?.single.cachedAt, now);
    expect(restored?.single.isOfflineCache, isTrue);
  });

  test('rejects a different or expired search query', () async {
    final preferences = SharedPreferencesAsync();
    const key = 'location-search-expiry';
    final cache = PersistentLocationSearchCache(
      preferences,
      storageKey: key,
      now: () => now,
    );
    await cache.write('西湖', onlineResults);

    expect(await cache.readMatching('灵隐寺'), isNull);
    final expired = PersistentLocationSearchCache(
      preferences,
      storageKey: key,
      now: () => now.add(const Duration(hours: 25)),
    );
    expect(await expired.readMatching('西湖'), isNull);
  });

  test(
    'uses cache for network failure but not configuration failure',
    () async {
      final primary = _MutableLocationSearchRepository(onlineResults);
      final cache = PersistentLocationSearchCache(
        SharedPreferencesAsync(),
        storageKey: 'location-search-resilient',
        now: () => now,
      );
      final repository = ResilientLocationSearchRepository(
        primary: primary,
        cache: cache,
      );
      expect((await repository.search('西湖')).single.isOfflineCache, isFalse);

      primary.failure = LocationSearchFailureKind.network;
      expect((await repository.search('西湖')).single.isOfflineCache, isTrue);

      primary.failure = LocationSearchFailureKind.configuration;
      await expectLater(
        repository.search('西湖'),
        throwsA(
          isA<LocationSearchFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocationSearchFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test('clear removes cached search text and coordinates', () async {
    final cache = PersistentLocationSearchCache(
      SharedPreferencesAsync(),
      storageKey: 'location-search-clear',
      now: () => now,
    );
    await cache.write('西湖', onlineResults);

    await cache.clear();

    expect(await cache.readMatching('西湖'), isNull);
  });
}

class _MutableLocationSearchRepository implements LocationSearchRepository {
  _MutableLocationSearchRepository(this.results);

  final List<LocationSearchResult> results;
  LocationSearchFailureKind? failure;

  @override
  Future<List<LocationSearchResult>> search(String keywords) async {
    if (failure case final kind?) throw LocationSearchFailure(kind);
    return results;
  }
}
