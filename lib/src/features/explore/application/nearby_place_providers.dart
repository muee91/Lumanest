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
  final location = snapshot.location;
  if (location == null) {
    throw const NearbyPlaceFailure(NearbyPlaceFailureKind.response);
  }
  final category = ref.watch(nearbyCategoryProvider);
  return ref
      .watch(nearbyPlaceRepositoryProvider)
      .fetchNearby(center: location, category: category);
});
