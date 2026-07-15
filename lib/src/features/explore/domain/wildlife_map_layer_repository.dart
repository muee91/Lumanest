import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';

abstract interface class WildlifeMapLayerRepository {
  Future<WildlifeMapLayer> fetch({
    required GeoPoint center,
    int radiusKilometers = 20,
  });
}

enum WildlifeMapLayerFailureKind { configuration, network, response }

class WildlifeMapLayerFailure implements Exception {
  const WildlifeMapLayerFailure(this.kind);

  final WildlifeMapLayerFailureKind kind;

  @override
  String toString() => 'WildlifeMapLayerFailure($kind)';
}
