import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/amap_driving_route_repository.dart';
import 'package:luma_nest/src/features/route/infrastructure/driving_route_cache.dart';
import 'package:luma_nest/src/features/route/infrastructure/route_support_cache.dart';
import 'package:luma_nest/src/features/route/infrastructure/resilient_driving_route_repository.dart';
import 'package:luma_nest/src/features/route/application/route_elevation_service.dart';
import 'package:luma_nest/src/features/route/infrastructure/data_broker_elevation_repository.dart';
import 'package:luma_nest/src/features/route/infrastructure/elevation_aware_route_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RouteDestination {
  const RouteDestination({
    required this.name,
    required this.point,
    this.travelMode = RouteTravelMode.driving,
  });

  final String name;
  final GeoPoint point;
  final RouteTravelMode travelMode;

  @override
  bool operator ==(Object other) =>
      other is RouteDestination &&
      other.name == name &&
      other.point.latitude == point.latitude &&
      other.point.longitude == point.longitude &&
      other.travelMode == travelMode;

  @override
  int get hashCode =>
      Object.hash(name, point.latitude, point.longitude, travelMode);
}

final drivingRouteCacheProvider = Provider<DrivingRouteCache>((ref) {
  return PersistentDrivingRouteCache(SharedPreferencesAsync());
});

final routeSupportCacheProvider = Provider<RouteSupportCache>((ref) {
  return PersistentRouteSupportCache(SharedPreferencesAsync());
});

final drivingRouteRepositoryProvider = Provider<DrivingRouteRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  final primary = AmapDrivingRouteRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioAmapRouteTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      ),
    ),
  );
  final cache = ref.watch(drivingRouteCacheProvider);
  final resilient = ResilientDrivingRouteRepository(
    primary: primary,
    cache: cache,
  );
  final elevationRepository = DataBrokerElevationProfileRepository(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    transport: DioElevationProfileTransport(
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      ),
    ),
  );
  return ElevationAwareRouteRepository(
    base: resilient,
    elevation: RouteElevationService(elevationRepository),
    cache: cache,
  );
});

final drivingRouteProvider =
    FutureProvider.family<DrivingRoute, RouteDestination>((
      ref,
      destination,
    ) async {
      final snapshot = await ref.watch(environmentSnapshotProvider.future);
      final origin = snapshot.location;
      if (origin == null) {
        throw const DrivingRouteFailure(DrivingRouteFailureKind.response);
      }
      return ref
          .watch(drivingRouteRepositoryProvider)
          .plan(
            DrivingRouteRequest(
              origin: origin,
              destination: destination.point,
              destinationName: destination.name,
              travelMode: destination.travelMode,
            ),
          );
    });
