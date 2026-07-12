import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';

abstract interface class WildlifeRepository {
  Future<RegionalWildlifeActivity> fetchRegionalWildlifeActivity(
    GeoPoint location,
  );
}

enum WildlifeFailureKind { configuration, network, response }

class WildlifeFailure implements Exception {
  const WildlifeFailure(this.kind);

  final WildlifeFailureKind kind;

  @override
  String toString() => 'WildlifeFailure($kind)';
}
