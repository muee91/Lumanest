import 'package:luma_nest/src/core/location/geo_point.dart';

enum RouteTravelMode { driving, walking }

class DrivingRouteRequest {
  const DrivingRouteRequest({
    required this.origin,
    required this.destination,
    required this.destinationName,
    this.travelMode = RouteTravelMode.driving,
  });

  final GeoPoint origin;
  final GeoPoint destination;
  final String destinationName;
  final RouteTravelMode travelMode;

  @override
  bool operator ==(Object other) =>
      other is DrivingRouteRequest &&
      other.origin.latitude == origin.latitude &&
      other.origin.longitude == origin.longitude &&
      other.destination.latitude == destination.latitude &&
      other.destination.longitude == destination.longitude &&
      other.destinationName == destinationName &&
      other.travelMode == travelMode;

  @override
  int get hashCode => Object.hash(
    origin.latitude,
    origin.longitude,
    destination.latitude,
    destination.longitude,
    destinationName,
    travelMode,
  );
}

class DrivingRoute {
  DrivingRoute({
    required this.destinationName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.tollsYuan,
    required List<GeoPoint> polyline,
    List<String> instructions = const [],
    this.isStale = false,
    this.cachedAt,
    this.travelMode = RouteTravelMode.driving,
    this.ascentMeters,
    this.descentMeters,
    this.elevationSource,
  }) : polyline = List.unmodifiable(polyline),
       instructions = List.unmodifiable(instructions);

  final String destinationName;
  final int distanceMeters;
  final int durationSeconds;
  final double tollsYuan;
  final List<GeoPoint> polyline;
  final List<String> instructions;
  final bool isStale;
  final DateTime? cachedAt;
  final RouteTravelMode travelMode;
  final int? ascentMeters;
  final int? descentMeters;
  final String? elevationSource;

  DrivingRoute asStale(DateTime savedAt) => DrivingRoute(
    destinationName: destinationName,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    tollsYuan: tollsYuan,
    polyline: polyline,
    instructions: instructions,
    isStale: true,
    cachedAt: savedAt.toUtc(),
    travelMode: travelMode,
    ascentMeters: ascentMeters,
    descentMeters: descentMeters,
    elevationSource: elevationSource,
  );

  DrivingRoute withElevation({
    required int ascentMeters,
    required int descentMeters,
    required String source,
  }) => DrivingRoute(
    destinationName: destinationName,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    tollsYuan: tollsYuan,
    polyline: polyline,
    instructions: instructions,
    isStale: isStale,
    cachedAt: cachedAt,
    travelMode: travelMode,
    ascentMeters: ascentMeters,
    descentMeters: descentMeters,
    elevationSource: source,
  );
}

abstract interface class DrivingRouteRepository {
  Future<DrivingRoute> plan(DrivingRouteRequest request);
}

enum DrivingRouteFailureKind { configuration, network, response }

class DrivingRouteFailure implements Exception {
  const DrivingRouteFailure(this.kind);

  final DrivingRouteFailureKind kind;

  @override
  String toString() => 'DrivingRouteFailure($kind)';
}
