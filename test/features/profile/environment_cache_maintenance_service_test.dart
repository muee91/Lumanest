import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/wildlife_map_layer_providers.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_cache.dart';
import 'package:luma_nest/src/features/profile/application/environment_cache_maintenance_service.dart';

void main() {
  test(
    'reports snapshot freshness and clears all environment caches',
    () async {
      final cache = InMemoryContextCache();
      final wildlifeCache = _FakeWildlifeMapLayerCache();
      final now = DateTime.now().toUtc();
      await cache.write(
        ContextSnapshot(
          id: 'local-cache',
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 10)),
          primaryScene: SceneType.lake,
          dayPhase: DayPhase.day,
          weather: WeatherType.clear,
          activeRoute: false,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          contextCacheProvider.overrideWithValue(cache),
          wildlifeMapLayerCacheProvider.overrideWithValue(wildlifeCache),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(
        environmentCacheMaintenanceServiceProvider,
      );
      final current = await service.status();
      expect(current.availability, EnvironmentCacheAvailability.current);
      expect(current.snapshot?.id, 'local-cache');

      await service.clear();

      expect(
        (await service.status()).availability,
        EnvironmentCacheAvailability.absent,
      );
      expect(wildlifeCache.cleared, isTrue);
    },
  );
}

class _FakeWildlifeMapLayerCache implements WildlifeMapLayerCache {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<WildlifeMapLayer?> readMatching({
    required GeoPoint center,
    required int radiusKilometers,
  }) async => null;

  @override
  Future<void> write({
    required GeoPoint center,
    required WildlifeMapLayer layer,
  }) async {}
}
