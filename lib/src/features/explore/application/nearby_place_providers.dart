import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/nearby_place_cache.dart';
import 'package:luma_nest/src/features/explore/infrastructure/resilient_nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

class NearbySearchArea {
  const NearbySearchArea({
    this.baseCenter,
    this.activeCenter,
    this.pendingCenter,
    this.radiusMeters = 5000,
  });

  final GeoPoint? baseCenter;
  final GeoPoint? activeCenter;
  final GeoPoint? pendingCenter;
  final int radiusMeters;

  bool get hasPendingMapArea => pendingCenter != null;

  NearbySearchArea copyWith({
    GeoPoint? baseCenter,
    GeoPoint? activeCenter,
    GeoPoint? pendingCenter,
    int? radiusMeters,
    bool clearActive = false,
    bool clearPending = false,
  }) => NearbySearchArea(
    baseCenter: baseCenter ?? this.baseCenter,
    activeCenter: clearActive ? null : activeCenter ?? this.activeCenter,
    pendingCenter: clearPending ? null : pendingCenter ?? this.pendingCenter,
    radiusMeters: radiusMeters ?? this.radiusMeters,
  );
}

class NearbySearchAreaController extends Notifier<NearbySearchArea> {
  @override
  NearbySearchArea build() => const NearbySearchArea();

  void syncBase(GeoPoint point) {
    final previous = state.baseCenter;
    if (previous != null &&
        previous.latitude == point.latitude &&
        previous.longitude == point.longitude) {
      return;
    }
    state = NearbySearchArea(baseCenter: point);
  }

  void markMapMoved(GeoPoint point) {
    state = state.copyWith(pendingCenter: point);
  }

  void searchPendingArea() {
    final pending = state.pendingCenter;
    if (pending == null) return;
    state = state.copyWith(activeCenter: pending, clearPending: true);
  }

  void expand() {
    final next = switch (state.radiusMeters) {
      < 15000 => 15000,
      < 30000 => 30000,
      _ => state.radiusMeters,
    };
    if (next != state.radiusMeters) {
      state = state.copyWith(radiusMeters: next);
    }
  }

  void resetRadius() {
    if (state.radiusMeters != 5000) {
      state = state.copyWith(radiusMeters: 5000);
    }
  }
}

final nearbySearchAreaProvider =
    NotifierProvider<NearbySearchAreaController, NearbySearchArea>(
      NearbySearchAreaController.new,
    );

final nearbyCategoryProvider = Provider<NearbyPlaceCategory>((ref) {
  return ref.watch(exploreIntentProvider).category;
});

final nearbyPlaceCacheProvider = Provider<NearbyPlaceCache>((ref) {
  return PersistentNearbyPlaceCache(SharedPreferencesAsync());
});

final nearbyPlaceRepositoryProvider = Provider<NearbyPlaceRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  final primary = AmapNearbyPlaceRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioAmapDataTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      ),
    ),
  );
  return ResilientNearbyPlaceRepository(
    primary: primary,
    cache: ref.watch(nearbyPlaceCacheProvider),
  );
});

final nearbyPlacesProvider = FutureProvider<List<NearbyPlace>>((ref) async {
  final snapshot = await ref.watch(environmentSnapshotProvider.future);
  final area = ref.watch(
    nearbySearchAreaProvider.select(
      (value) => (center: value.activeCenter, radiusMeters: value.radiusMeters),
    ),
  );
  final location = area.center ?? snapshot.location;
  if (location == null) {
    throw const NearbyPlaceFailure(NearbyPlaceFailureKind.response);
  }
  final category = ref.watch(nearbyCategoryProvider);
  return ref
      .watch(nearbyPlaceRepositoryProvider)
      .fetchNearby(
        center: location,
        category: category,
        radiusMeters: area.radiusMeters,
      );
});
