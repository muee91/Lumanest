import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/application/wildlife_map_layer_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/infrastructure/nearby_place_cache.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_cache.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/base_region.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/base_region_store.dart';
import 'package:luma_nest/src/features/location/infrastructure/location_search_cache.dart';
import 'package:luma_nest/src/features/profile/application/environment_privacy_service.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';
import 'package:luma_nest/src/features/route/infrastructure/route_support_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../explore/map_consent_test_harness.dart';

void main() {
  test('revokes environment use and clears only environment state', () async {
    final consentStore = _FakeConsentStore(true);
    final mapConsentStore = FakeMapConsentStore(granted: true);
    final cache = InMemoryContextCache();
    final cacheWriteGuard = ContextCacheWriteGuard();
    final baseRegionStore = _FakeBaseRegionStore();
    final routeCache = _FakeDrivingRouteCache();
    final supportCache = _FakeRouteSupportCache();
    final locationSearchCache = _FakeLocationSearchCache();
    final nearbyPlaceCache = _FakeNearbyPlaceCache();
    final wildlifeMapLayerCache = _FakeWildlifeMapLayerCache();
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
        drivingRouteCacheProvider.overrideWithValue(routeCache),
        routeSupportCacheProvider.overrideWithValue(supportCache),
        locationSearchCacheProvider.overrideWithValue(locationSearchCache),
        nearbyPlaceCacheProvider.overrideWithValue(nearbyPlaceCache),
        wildlifeMapLayerCacheProvider.overrideWithValue(wildlifeMapLayerCache),
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
    expect(routeCache.cleared, isTrue);
    expect(supportCache.cleared, isTrue);
    expect(locationSearchCache.cleared, isTrue);
    expect(nearbyPlaceCache.cleared, isTrue);
    expect(wildlifeMapLayerCache.cleared, isTrue);
  });
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

class _FakeLocationSearchCache implements LocationSearchCache {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<List<LocationSearchResult>?> readMatching(String keywords) async =>
      null;

  @override
  Future<void> write(
    String keywords,
    List<LocationSearchResult> results,
  ) async {}
}

class _FakeNearbyPlaceCache implements NearbyPlaceCache {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<List<NearbyPlace>?> readMatching({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    required int radiusMeters,
  }) async => null;

  @override
  Future<void> write({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    required int radiusMeters,
    required List<NearbyPlace> places,
  }) async {}
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

class _FakeDrivingRouteCache implements DrivingRouteCache {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<DrivingRoute?> readMatching(DrivingRouteRequest request) async => null;

  @override
  Future<void> write(DrivingRouteRequest request, DrivingRoute route) async {}
}

class _FakeRouteSupportCache implements RouteSupportCache {
  bool cleared = false;

  @override
  Future<void> clear() async => cleared = true;

  @override
  Future<List<RouteSupportStop>?> readMatching(DrivingRoute route) async =>
      null;

  @override
  Future<void> write(DrivingRoute route, List<RouteSupportStop> stops) async {}
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
