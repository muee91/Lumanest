import 'package:luma_nest/src/features/route/application/route_elevation_service.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';

class ElevationAwareRouteRepository implements DrivingRouteRepository {
  const ElevationAwareRouteRepository({
    required this.base,
    required this.elevation,
    required this.cache,
  });

  final DrivingRouteRepository base;
  final RouteElevationService elevation;
  final DrivingRouteCache cache;

  @override
  Future<DrivingRoute> plan(DrivingRouteRequest request) async {
    final route = await base.plan(request);
    if (request.travelMode != RouteTravelMode.walking || route.isStale) {
      return route;
    }
    try {
      final enriched = await elevation.enrich(route);
      await cache.write(request, enriched);
      return enriched;
    } on Object {
      return route;
    }
  }
}
