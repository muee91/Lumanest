import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/application/wildlife_map_layer_providers.dart';
import 'package:luma_nest/src/features/location/application/manual_location_providers.dart';
import 'package:luma_nest/src/features/location/application/base_region_controller.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';

abstract interface class EnvironmentPrivacyService {
  Future<void> revokeAndClear();
}

class RiverpodEnvironmentPrivacyService implements EnvironmentPrivacyService {
  RiverpodEnvironmentPrivacyService(this._ref);

  final Ref _ref;

  @override
  Future<void> revokeAndClear() async {
    // Close the cache to every request that started before this privacy clear.
    // A late network response must never recreate data after the user removes
    // it.
    _ref.read(contextCacheWriteGuardProvider).invalidate();

    // Stop new environment work before removing any stored state.
    await _ref.read(environmentConsentProvider.notifier).revoke();
    await _ref.read(mapConsentControllerProvider.notifier).revokeConsent();
    await _ref.read(manualLocationProvider.notifier).clear();
    await _ref.read(baseRegionProvider.notifier).clear();
    await _ref.read(contextCacheProvider).clear();
    await _ref.read(drivingRouteCacheProvider).clear();
    await _ref.read(routeSupportCacheProvider).clear();
    await _ref.read(locationSearchCacheProvider).clear();
    await _ref.read(nearbyPlaceCacheProvider).clear();
    await _ref.read(wildlifeMapLayerCacheProvider).clear();
    await _ref.read(appDatabaseProvider).clearDerivedCaches();

    // Drop in-memory snapshots and generated wording. These providers stay
    // dormant while consent is false and rebuild only after a new opt-in.
    _ref.invalidate(environmentSnapshotProvider);
    _ref.invalidate(manifestNarrativeCoordinatorProvider);
    _ref.invalidate(wildlifeMapLayerProvider);
  }
}

final environmentPrivacyServiceProvider = Provider<EnvironmentPrivacyService>(
  RiverpodEnvironmentPrivacyService.new,
);
