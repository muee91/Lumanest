import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/application/wildlife_map_layer_providers.dart';

enum EnvironmentCacheAvailability { absent, current, stale }

class EnvironmentCacheStatus {
  const EnvironmentCacheStatus({required this.availability, this.snapshot});

  final EnvironmentCacheAvailability availability;
  final ContextSnapshot? snapshot;
}

abstract interface class EnvironmentCacheMaintenanceService {
  Future<EnvironmentCacheStatus> status();
  Future<void> clear();
}

class RiverpodEnvironmentCacheMaintenanceService
    implements EnvironmentCacheMaintenanceService {
  RiverpodEnvironmentCacheMaintenanceService(this._ref);

  final Ref _ref;

  @override
  Future<EnvironmentCacheStatus> status() async {
    final snapshot = await _ref.read(contextCacheProvider).readLatest();
    if (snapshot == null) {
      return const EnvironmentCacheStatus(
        availability: EnvironmentCacheAvailability.absent,
      );
    }
    final current =
        !snapshot.isStale &&
        snapshot.expiresAt.toUtc().isAfter(DateTime.now().toUtc());
    return EnvironmentCacheStatus(
      availability: current
          ? EnvironmentCacheAvailability.current
          : EnvironmentCacheAvailability.stale,
      snapshot: snapshot,
    );
  }

  @override
  Future<void> clear() async {
    _ref.read(contextCacheWriteGuardProvider).invalidate();
    await Future.wait([
      _ref.read(contextCacheProvider).clear(),
      _ref.read(wildlifeMapLayerCacheProvider).clear(),
    ]);
    _ref.invalidate(wildlifeMapLayerProvider);
  }
}

final environmentCacheMaintenanceServiceProvider =
    Provider<EnvironmentCacheMaintenanceService>(
      RiverpodEnvironmentCacheMaintenanceService.new,
    );

final environmentCacheStatusProvider = FutureProvider<EnvironmentCacheStatus>((
  ref,
) {
  return ref.watch(environmentCacheMaintenanceServiceProvider).status();
});
