import 'package:luma_nest/src/core/location/location_reading.dart';

enum LocationFailureKind {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

/// Sanitized location failure that presentation code can safely map to a
/// recovery action without depending on a platform adapter.
class LocationRepositoryFailure implements Exception {
  const LocationRepositoryFailure(this.kind);

  final LocationFailureKind kind;

  @override
  String toString() => 'LocationRepositoryFailure($kind)';
}

abstract interface class LocationRepository {
  Future<LocationReading> current();
}
