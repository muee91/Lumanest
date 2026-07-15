import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_cache.dart';

class ResilientWildlifeMapLayerRepository
    implements WildlifeMapLayerRepository {
  const ResilientWildlifeMapLayerRepository({
    required this.primary,
    required this.cache,
    required this.writeGuard,
  });

  final WildlifeMapLayerRepository primary;
  final WildlifeMapLayerCache cache;
  final ContextCacheWriteGuard writeGuard;

  @override
  Future<WildlifeMapLayer> fetch({
    required GeoPoint center,
    int radiusKilometers = 20,
  }) async {
    final generation = writeGuard.begin();
    try {
      final layer = await primary.fetch(
        center: center,
        radiusKilometers: radiusKilometers,
      );
      if (writeGuard.allows(generation)) {
        try {
          await cache.write(center: center, layer: layer);
        } on Object {
          // A cache write failure must not hide a valid reviewed layer.
        }
      }
      return layer;
    } on WildlifeMapLayerFailure catch (failure) {
      if (failure.kind == WildlifeMapLayerFailureKind.configuration) rethrow;
      try {
        final cached = await cache.readMatching(
          center: center,
          radiusKilometers: radiusKilometers,
        );
        if (cached != null) return cached;
      } on Object {
        // Preserve the bounded network/response failure instead of exposing a
        // local database error through the UI.
      }
      rethrow;
    }
  }
}
