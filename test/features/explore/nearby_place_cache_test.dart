import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/nearby_place_cache.dart';
import 'package:luma_nest/src/features/explore/infrastructure/resilient_nearby_place_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 8);
  const center = GeoPoint(latitude: 30.231, longitude: 120.132);
  const places = [
    NearbyPlace(
      id: 'viewpoint-1',
      name: '湖岸观景台',
      category: NearbyPlaceCategory.viewpoint,
      point: GeoPoint(
        latitude: 30.232,
        longitude: 120.134,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
      distanceMeters: 320,
      address: '湖岸路',
      media: [
        NearbyPlaceMedia(
          id: '1234567890abcdef12345678',
          url: 'https://broker.example/v1/amap/media/photo-token',
          attribution: '高德地图',
          title: '湖岸观景台',
        ),
      ],
    ),
  ];

  test(
    'restores only a nearby matching category and radius without provider media',
    () async {
      final cache = PersistentNearbyPlaceCache(
        SharedPreferencesAsync(),
        storageKey: 'nearby-place-roundtrip',
        now: () => now,
      );
      await cache.write(
        center: center,
        category: NearbyPlaceCategory.viewpoint,
        radiusMeters: 5000,
        places: places,
      );

      final restored = await cache.readMatching(
        center: const GeoPoint(latitude: 30.232, longitude: 120.133),
        category: NearbyPlaceCategory.viewpoint,
        radiusMeters: 5000,
      );

      expect(restored?.single.name, '湖岸观景台');
      expect(restored?.single.cachedAt, now);
      expect(restored?.single.isOfflineCache, isTrue);
      expect(restored?.single.coverMedia, isNull);
      expect(
        await cache.readMatching(
          center: center,
          category: NearbyPlaceCategory.food,
          radiusMeters: 5000,
        ),
        isNull,
      );
      expect(
        await cache.readMatching(
          center: center,
          category: NearbyPlaceCategory.viewpoint,
          radiusMeters: 3000,
        ),
        isNull,
      );
    },
  );

  test('rejects far-away and expired nearby results', () async {
    final preferences = SharedPreferencesAsync();
    const key = 'nearby-place-expiry';
    final cache = PersistentNearbyPlaceCache(
      preferences,
      storageKey: key,
      now: () => now,
    );
    await cache.write(
      center: center,
      category: NearbyPlaceCategory.viewpoint,
      radiusMeters: 5000,
      places: places,
    );

    expect(
      await cache.readMatching(
        center: const GeoPoint(latitude: 30.25, longitude: 120.15),
        category: NearbyPlaceCategory.viewpoint,
        radiusMeters: 5000,
      ),
      isNull,
    );
    final expired = PersistentNearbyPlaceCache(
      preferences,
      storageKey: key,
      now: () => now.add(const Duration(hours: 25)),
    );
    expect(
      await expired.readMatching(
        center: center,
        category: NearbyPlaceCategory.viewpoint,
        radiusMeters: 5000,
      ),
      isNull,
    );
  });

  test(
    'uses cache for response failure but not configuration failure',
    () async {
      final primary = _MutableNearbyPlaceRepository(places);
      final cache = PersistentNearbyPlaceCache(
        SharedPreferencesAsync(),
        storageKey: 'nearby-place-resilient',
        now: () => now,
      );
      final repository = ResilientNearbyPlaceRepository(
        primary: primary,
        cache: cache,
      );
      expect(
        (await repository.fetchNearby(
          center: center,
          category: NearbyPlaceCategory.viewpoint,
        )).single.isOfflineCache,
        isFalse,
      );

      primary.failure = NearbyPlaceFailureKind.response;
      expect(
        (await repository.fetchNearby(
          center: center,
          category: NearbyPlaceCategory.viewpoint,
        )).single.isOfflineCache,
        isTrue,
      );

      primary.failure = NearbyPlaceFailureKind.configuration;
      await expectLater(
        repository.fetchNearby(
          center: center,
          category: NearbyPlaceCategory.viewpoint,
        ),
        throwsA(
          isA<NearbyPlaceFailure>().having(
            (failure) => failure.kind,
            'kind',
            NearbyPlaceFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test('clear removes cached nearby coordinates', () async {
    final cache = PersistentNearbyPlaceCache(
      SharedPreferencesAsync(),
      storageKey: 'nearby-place-clear',
      now: () => now,
    );
    await cache.write(
      center: center,
      category: NearbyPlaceCategory.viewpoint,
      radiusMeters: 5000,
      places: places,
    );

    await cache.clear();

    expect(
      await cache.readMatching(
        center: center,
        category: NearbyPlaceCategory.viewpoint,
        radiusMeters: 5000,
      ),
      isNull,
    );
  });
}

class _MutableNearbyPlaceRepository implements NearbyPlaceRepository {
  _MutableNearbyPlaceRepository(this.places);

  final List<NearbyPlace> places;
  NearbyPlaceFailureKind? failure;

  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    if (failure case final kind?) throw NearbyPlaceFailure(kind);
    return places;
  }
}
