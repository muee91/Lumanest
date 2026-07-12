import 'package:luma_nest/src/core/location/geo_point.dart';

class DrivingRouteRequest {
  const DrivingRouteRequest({
    required this.origin,
    required this.destination,
    required this.destinationName,
  });

  final GeoPoint origin;
  final GeoPoint destination;
  final String destinationName;

  @override
  bool operator ==(Object other) =>
      other is DrivingRouteRequest &&
      other.origin.latitude == origin.latitude &&
      other.origin.longitude == origin.longitude &&
      other.destination.latitude == destination.latitude &&
      other.destination.longitude == destination.longitude &&
      other.destinationName == destinationName;

  @override
  int get hashCode => Object.hash(
    origin.latitude,
    origin.longitude,
    destination.latitude,
    destination.longitude,
    destinationName,
  );
}

class DrivingRoute {
  DrivingRoute({
    required this.destinationName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.tollsYuan,
    required this.polyline,
    List<String> instructions = const [],
  }) : instructions = List.unmodifiable(instructions);

  final String destinationName;
  final int distanceMeters;
  final int durationSeconds;
  final double tollsYuan;
  final List<GeoPoint> polyline;
  final List<String> instructions;
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
