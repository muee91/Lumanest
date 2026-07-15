import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/location/domain/base_region.dart';
import 'package:luma_nest/src/features/location/infrastructure/base_region_store.dart';
import 'package:luma_nest/src/features/profile/application/environment_privacy_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../explore/map_consent_test_harness.dart';

void main() {
  test('revokes environment use and clears only environment state', () async {
    final consentStore = _FakeConsentStore(true);
    final mapConsentStore = FakeMapConsentStore(granted: true);
    final cache = InMemoryContextCache();
    final cacheWriteGuard = ContextCacheWriteGuard();
    final baseRegionStore = _FakeBaseRegionStore();
    final gateway = FakeAmapInitializerGateway();
    final now = DateTime.utc(2026, 7, 13, 10);
    await cache.write(
      ContextSnapshot(
        id: 'private-context',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        environmentConsentStoreProvider.overrideWithValue(consentStore),
        contextCacheProvider.overrideWithValue(cache),
        contextCacheWriteGuardProvider.overrideWithValue(cacheWriteGuard),
        environmentConfigProvider.overrideWithValue(
          EnvironmentConfig(amapAndroidKey: 'test-key'),
        ),
        amapInitializerGatewayProvider.overrideWithValue(gateway),
        mapConsentStoreProvider.overrideWithValue(mapConsentStore),
        baseRegionStoreProvider.overrideWithValue(baseRegionStore),
      ],
    );
    addTearDown(container.dispose);
    container.read(environmentConsentProvider);
    await Future<void>.delayed(Duration.zero);
    container.read(mapConsentControllerProvider.notifier).grantConsent();

    await container.read(environmentPrivacyServiceProvider).revokeAndClear();

    expect(container.read(environmentConsentProvider), isFalse);
    expect(consentStore.granted, isFalse);
    expect(await cache.readLatest(), isNull);
    expect(cacheWriteGuard.generation, 1);
    expect(
      container.read(mapConsentControllerProvider),
      isA<MapConsentAwaiting>(),
    );
    expect(gateway.lastStatement?.hasAgree, isFalse);
    expect(mapConsentStore.granted, isFalse);
    expect(baseRegionStore.cleared, isTrue);
  });
}

class _FakeBaseRegionStore implements BaseRegionStore {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<BaseRegion?> read() async => null;

  @override
  Future<void> write(BaseRegion value) async {}
}

class _FakeConsentStore implements EnvironmentConsentStore {
  _FakeConsentStore(this.granted);
  bool granted;

  @override
  Future<bool?> readGranted() async => granted;

  @override
  Future<void> writeGranted(bool granted) async {
    this.granted = granted;
  }
}
