import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/location_search_cache.dart';

class ResilientLocationSearchRepository implements LocationSearchRepository {
  const ResilientLocationSearchRepository({
    required this.primary,
    required this.cache,
  });

  final LocationSearchRepository primary;
  final LocationSearchCache cache;

  @override
  Future<List<LocationSearchResult>> search(
    String keywords, {
    GeoPoint? center,
  }) async {
    try {
      final results = await primary.search(keywords, center: center);
      if (results.isNotEmpty) {
        try {
          await cache.write(keywords, results, center: center);
        } on Object {
          // A cache write must not turn a valid online result into a failure.
        }
      }
      return results;
    } on LocationSearchFailure catch (failure) {
      if (failure.kind == LocationSearchFailureKind.configuration) rethrow;
      final cached = await cache.readMatching(keywords, center: center);
      if (cached != null) return cached;
      rethrow;
    }
  }
}
