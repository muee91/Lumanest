import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

abstract interface class RemoteContextRepository {
  Future<ContextSnapshot> fetchSnapshot({
    required LocationReading location,
    required DateTime observedAt,
    RouteContextState route = RouteContextState.none,
    RouteCorridorContext? corridor,
  });

  Future<ContextSnapshot> enrich({
    required ContextSnapshot base,
    required WeatherObservation weather,
    required SolarState solar,
  });
}

enum RemoteContextFailureKind {
  configuration,
  network,
  serviceUnavailable,
  response,
  unsupportedContract,
}

class RemoteContextFailure implements Exception {
  const RemoteContextFailure(this.kind);

  final RemoteContextFailureKind kind;

  @override
  String toString() => 'RemoteContextFailure($kind)';
}
