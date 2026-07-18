import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';

abstract interface class RemoteContextRepository {
  Future<ContextSnapshot> fetchSnapshot({
    required LocationReading location,
    required DateTime observedAt,
    RouteContextState route = RouteContextState.none,
    RouteCorridorContext? corridor,
  });
}

enum RemoteContextFailureKind {
  configuration,
  network,
  serviceUnavailable,
  response,
}

class RemoteContextFailure implements Exception {
  const RemoteContextFailure(this.kind);

  final RemoteContextFailureKind kind;

  @override
  String toString() => 'RemoteContextFailure($kind)';
}
