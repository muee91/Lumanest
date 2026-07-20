import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/context_entry_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_candidate_ranker.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_context.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_engine.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_discovery_result.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/domain/popular_place_evidence.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_popular_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/nearby_place_cache.dart';
import 'package:luma_nest/src/features/explore/infrastructure/resilient_nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/verified_place_media_repository.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final nearbyDiscoveryEngineProvider = Provider<NearbyDiscoveryEngine>((ref) {
  return const NearbyDiscoveryEngine();
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
  final placesFuture = fetchOptionalNearbyPlaces(
    ref.watch(nearbyPlaceRepositoryProvider),
    center: location,
    category: category,
    radiusMeters: area.radiusMeters,
  );
  final candidateMode =
      category == NearbyPlaceCategory.sunriseCandidate ||
      category == NearbyPlaceCategory.nightSkyCandidate;
  final discoveryEnabled = switch (category) {
    NearbyPlaceCategory.viewpoint ||
    NearbyPlaceCategory.sunriseCandidate ||
    NearbyPlaceCategory.nightSkyCandidate ||
    NearbyPlaceCategory.waterfront ||
    NearbyPlaceCategory.humanity => true,
    _ => false,
  };
  final discoveryContext = NearbyDiscoveryContext(
    origin: snapshot.location ?? location,
    searchCenter: location,
    radiusMeters: area.radiusMeters,
    intent: category,
    mode: NearbyDiscoveryMode.explicit,
    now: ref.watch(currentTimeProvider)(),
    snapshot: snapshot,
  );

  if (!discoveryEnabled) {
    final places = await placesFuture;
    final result = ref
        .watch(nearbyDiscoveryEngineProvider)
        .rank(places, discoveryContext);
    return _publishNearbyDiscovery(ref, result);
  }

  final evidenceFuture = fetchOptionalPopularPlaceEvidence(
    ref.watch(popularPlaceEvidenceRepositoryProvider),
    center: location,
    radiusMeters: area.radiusMeters,
    focus: _discoveryFocus(category, null),
  );
  final (places, evidence) = await (placesFuture, evidenceFuture).wait;
  final merged = NearbyCandidateRanker.mergeEvidence(places, evidence, category);
  final shortlist = NearbyCandidateRanker.shortlist(merged);
  final routed = candidateMode
      ? await _withDrivingTimes(
          shortlist,
          origin: location,
          repository: ref.watch(drivingRouteRepositoryProvider),
        )
      : shortlist;
  final result = ref
      .watch(nearbyDiscoveryEngineProvider)
      .rank(routed, discoveryContext);
  return _publishNearbyDiscovery(ref, result);
});

List<NearbyPlace> _publishNearbyDiscovery(
  Ref ref,
  NearbyDiscoveryResult result,
) {
  final store = ref.read(contextEntryStoreProvider);
  final nextIds = result.entries.map((entry) => entry.id).toSet();
  final removeIds = store
      .query(const EntryQuery(surface: EntrySurface.explore, kind: EntryKind.place))
      .where(
        (entry) =>
            entry.sourceNamespace == 'lumanest.local-entry-adapter' &&
            !nextIds.contains(entry.id),
      )
      .map((entry) => entry.id)
      .toSet();
  store.apply(
    EntryBatch(
      entries: result.entries,
      sourceRevision: result.observedAt.toUtc().microsecondsSinceEpoch,
      removeIds: removeIds,
    ),
  );
  return result.places;
}

Future<List<PopularPlaceEvidence>> fetchOptionalPopularPlaceEvidence(
  PopularPlaceEvidenceRepository repository, {
  required GeoPoint center,
  required int radiusMeters,
  required String focus,
}) async {
  try {
    return await repository.fetch(
      center: center,
      radiusMeters: radiusMeters,
      focus: focus,
    );
  } on Object {
    return const <PopularPlaceEvidence>[];
  }
}

Future<List<NearbyPlace>> fetchOptionalNearbyPlaces(
  NearbyPlaceRepository repository, {
  required GeoPoint center,
  required NearbyPlaceCategory category,
  required int radiusMeters,
}) async {
  try {
    return await repository.fetchNearby(
      center: center,
      category: category,
      radiusMeters: radiusMeters,
    );
  } on Object {
    return const <NearbyPlace>[];
  }
}

String _discoveryFocus(NearbyPlaceCategory category, String? city) {
  final region = city?.trim().isNotEmpty == true ? city!.trim() : '当前位置';
  final subject = switch (category) {
    NearbyPlaceCategory.sunriseCandidate => '日出摄影地点',
    NearbyPlaceCategory.nightSkyCandidate => '夜空摄影地点',
    NearbyPlaceCategory.waterfront => '水岸公园和滨水景观地点',
    NearbyPlaceCategory.humanity => '人文街巷、传统建筑和文化空间',
    _ => '公开资料提及的观景地点',
  };
  return '$region及周边$subject';
}

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
