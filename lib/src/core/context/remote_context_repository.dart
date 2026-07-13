import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

abstract interface class RemoteContextRepository {
  Future<ContextSnapshot> enrich({
    required ContextSnapshot base,
    required WeatherObservation weather,
    required SolarState solar,
  });
}

enum RemoteContextFailureKind { configuration, network, response }

class RemoteContextFailure implements Exception {
  const RemoteContextFailure(this.kind);

  final RemoteContextFailureKind kind;

  @override
  String toString() => 'RemoteContextFailure($kind)';
}
