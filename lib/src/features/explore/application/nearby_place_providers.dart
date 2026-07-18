import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/nearby_place_cache.dart';
import 'package:luma_nest/src/features/explore/infrastructure/resilient_nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/verified_place_media_repository.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_candidate_ranker.dart';
import 'package:luma_nest/src/features/explore/domain/popular_place_evidence.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_popular_place_repository.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
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
    state = state.copyWith(baseCenter: point);
  }

  void markMapMoved(GeoPoint point) {
    state = state.copyWith(pendingCenter: point);
  }

  void searchPendingArea() {
    final pending = state.pendingCenter;
    if (pending == null) return;
    state = state.copyWith(activeCenter: pending, clearPending: true);
  }

  void returnToBase() {
    if (state.activeCenter == null && state.pendingCenter == null) return;
    state = state.copyWith(clearActive: true, clearPending: true);
  }

  void returnToLocation(GeoPoint point) {
    state = NearbySearchArea(
      baseCenter: point,
      activeCenter: point,
      radiusMeters: state.radiusMeters,
    );
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

  void useDrivingCandidateRadius() {
    if (state.radiusMeters != 50000) {
      state = state.copyWith(radiusMeters: 50000);
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

final popularPlaceEvidenceRepositoryProvider =
    Provider<PopularPlaceEvidenceRepository>((ref) {
      final config = ref.watch(environmentConfigProvider);
      return DataBrokerPopularPlaceEvidenceRepository(
        brokerBaseUrl: config.dataBrokerBaseUrl,
        serviceToken: config.lumaNestServiceToken,
        transport: DioPopularPlaceEvidenceTransport(
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 8),
            ),
          ),
        ),
      );
    });

final verifiedPlaceMediaRepositoryProvider =
    Provider<VerifiedPlaceMediaRepository>((ref) {
      final config = ref.watch(environmentConfigProvider);
      return VerifiedPlaceMediaRepository(
        brokerBaseUrl: config.dataBrokerBaseUrl,
        serviceToken: config.lumaNestServiceToken,
        transport: DioVerifiedPlaceMediaTransport(
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 8),
            ),
          ),
        ),
      );
    });

final verifiedPlaceMediaProvider = FutureProvider.autoDispose
    .family<NearbyPlaceMedia?, NearbyPlace>(
      (ref, place) =>
          ref.watch(verifiedPlaceMediaRepositoryProvider).fetch(place),
    );

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
  final places = await ref
      .watch(nearbyPlaceRepositoryProvider)
      .fetchNearby(
        center: location,
        category: category,
        radiusMeters: area.radiusMeters,
      );
  final candidateMode =
      category == NearbyPlaceCategory.sunriseCandidate ||
      category == NearbyPlaceCategory.nightSkyCandidate;
  if (!candidateMode) return places;

  final nearestCity = places
      .map((place) => place.cityName)
      .whereType<String>()
      .firstOrNull;
  final evidence = await ref
      .watch(popularPlaceEvidenceRepositoryProvider)
      .fetch(
        center: location,
        radiusMeters: area.radiusMeters,
        focus:
            '${nearestCity ?? '当前位置'}及周边${category == NearbyPlaceCategory.sunriseCandidate ? '日出' : '夜空'}摄影地点',
      );
  final merged = NearbyCandidateRanker.mergeEvidence(
    places,
    evidence,
    category,
  );
  final shortlist = NearbyCandidateRanker.shortlist(merged);
  final routed = await _withDrivingTimes(
    shortlist,
    origin: location,
    repository: ref.watch(drivingRouteRepositoryProvider),
  );
  return NearbyCandidateRanker.rank(routed, radiusMeters: area.radiusMeters);
});

Future<List<NearbyPlace>> _withDrivingTimes(
  List<NearbyPlace> places, {
  required GeoPoint origin,
  required DrivingRouteRepository repository,
}) async {
  final results = <NearbyPlace>[];
  for (var index = 0; index < places.length; index += 2) {
    final batch = places.skip(index).take(2);
    results.addAll(
      await Future.wait(
        batch.map((place) async {
          try {
            final route = await repository.plan(
              DrivingRouteRequest(
                origin: origin,
                destination: place.point,
                destinationName: place.name,
              ),
            );
            return place.copyWith(
              drivingDurationSeconds: route.durationSeconds,
              drivingDistanceMeters: route.distanceMeters,
            );
          } on Object {
            return place;
          }
        }),
      ),
    );
    if (index + 2 < places.length) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  return List.unmodifiable(results);
}
