import 'package:luma_nest/src/core/location/geo_point.dart';

class LocationSearchResult {
  const LocationSearchResult({
    required this.id,
    required this.name,
    required this.point,
    this.address,
    this.distanceMeters,
    this.cachedAt,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final String? address;
  final int? distanceMeters;
  final DateTime? cachedAt;

  bool get isOfflineCache => cachedAt != null;
}

abstract interface class LocationSearchRepository {
  Future<List<LocationSearchResult>> search(
    String keywords, {
    GeoPoint? center,
  });
}

enum LocationSearchFailureKind { configuration, network, response }

class LocationSearchFailure implements Exception {
  const LocationSearchFailure(this.kind);

  final LocationSearchFailureKind kind;

  @override
  String toString() => 'LocationSearchFailure($kind)';
}
