import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/profile/application/environment_cache_maintenance_service.dart';

void main() {
  test('reports cache freshness and clears only the cached snapshot', () async {
    final cache = InMemoryContextCache();
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
      overrides: [contextCacheProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    final service = container.read(environmentCacheMaintenanceServiceProvider);
    final current = await service.status();
    expect(current.availability, EnvironmentCacheAvailability.current);
    expect(current.snapshot?.id, 'local-cache');

    await service.clear();

    expect(
      (await service.status()).availability,
      EnvironmentCacheAvailability.absent,
    );
  });
}
