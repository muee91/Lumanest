import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

abstract interface class NearbyPlaceRepository {
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  });
}

enum NearbyPlaceFailureKind { configuration, network, response }

class NearbyPlaceFailure implements Exception {
  const NearbyPlaceFailure(this.kind);

  final NearbyPlaceFailureKind kind;

  @override
  String toString() => 'NearbyPlaceFailure($kind)';
}
