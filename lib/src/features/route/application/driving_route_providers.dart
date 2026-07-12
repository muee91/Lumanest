import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/amap_driving_route_repository.dart';

class RouteDestination {
  const RouteDestination({required this.name, required this.point});

  final String name;
  final GeoPoint point;

  @override
  bool operator ==(Object other) =>
      other is RouteDestination &&
      other.name == name &&
      other.point.latitude == point.latitude &&
      other.point.longitude == point.longitude;

  @override
  int get hashCode => Object.hash(name, point.latitude, point.longitude);
}

final drivingRouteRepositoryProvider = Provider<DrivingRouteRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return AmapDrivingRouteRepository(
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
            ),
          );
    });
