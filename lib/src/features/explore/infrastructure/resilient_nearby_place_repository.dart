import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/nearby_place_cache.dart';

class ResilientNearbyPlaceRepository implements NearbyPlaceRepository {
  const ResilientNearbyPlaceRepository({
    required this.primary,
    required this.cache,
  });

  final NearbyPlaceRepository primary;
  final NearbyPlaceCache cache;

  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    try {
      final places = await primary.fetchNearby(
        center: center,
        category: category,
        radiusMeters: radiusMeters,
      );
      if (places.isNotEmpty) {
        try {
          await cache.write(
            center: center,
            category: category,
            radiusMeters: radiusMeters,
            places: places,
          );
        } on Object {
          // A cache write must not turn a valid online result into a failure.
        }
      }
      return places;
    } on NearbyPlaceFailure catch (failure) {
      if (failure.kind == NearbyPlaceFailureKind.configuration) rethrow;
      final cached = await cache.readMatching(
        center: center,
        category: category,
        radiusMeters: radiusMeters,
      );
      if (cached != null) return cached;
      rethrow;
    }
  }
}
