import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';

class ResilientDrivingRouteRepository implements DrivingRouteRepository {
  const ResilientDrivingRouteRepository({
    required this.primary,
    required this.cache,
  });

  final DrivingRouteRepository primary;
  final DrivingRouteCache cache;

  @override
  Future<DrivingRoute> plan(DrivingRouteRequest request) async {
    try {
      final route = await primary.plan(request);
      await cache.write(request, route);
      return route;
    } catch (error, stackTrace) {
      final cached = await cache.readMatching(request);
      if (cached != null) return cached;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
