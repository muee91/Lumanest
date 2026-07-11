import 'package:geolocator/geolocator.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';

enum PlatformLocationPermission { denied, deniedForever, whileInUse, always }

class PlatformPosition {
  const PlatformPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.altitudeMeters,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double altitudeMeters;
  final DateTime recordedAt;
}

abstract interface class LocationPlatformGateway {
  Future<bool> isServiceEnabled();

  Future<PlatformLocationPermission> checkPermission();

  Future<PlatformLocationPermission> requestPermission();

  Future<PlatformPosition> getCurrentPosition();
}

enum LocationFailureKind {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationRepositoryFailure implements Exception {
  const LocationRepositoryFailure(this.kind);

  final LocationFailureKind kind;

  @override
  String toString() => 'LocationRepositoryFailure($kind)';
}

class GeolocatorRepository implements LocationRepository {
  const GeolocatorRepository(this._gateway);

  final LocationPlatformGateway _gateway;

  @override
  Future<LocationReading> current() async {
    if (!await _gateway.isServiceEnabled()) {
      throw const LocationRepositoryFailure(
        LocationFailureKind.serviceDisabled,
      );
    }

    var permission = await _gateway.checkPermission();
    if (permission == PlatformLocationPermission.deniedForever) {
      throw const LocationRepositoryFailure(
        LocationFailureKind.permissionDeniedForever,
      );
    }
    if (permission == PlatformLocationPermission.denied) {
      permission = await _gateway.requestPermission();
    }
    if (permission == PlatformLocationPermission.deniedForever) {
      throw const LocationRepositoryFailure(
        LocationFailureKind.permissionDeniedForever,
      );
    }
    if (permission == PlatformLocationPermission.denied) {
      throw const LocationRepositoryFailure(
        LocationFailureKind.permissionDenied,
      );
    }

    try {
      final position = await _gateway.getCurrentPosition();
      final point = GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      ).validate();
      return LocationReading(
        point: point,
        recordedAt: position.recordedAt,
        accuracyMeters: position.accuracyMeters,
        altitudeMeters: position.altitudeMeters,
      );
    } on LocationRepositoryFailure {
      rethrow;
    } on Object {
      throw const LocationRepositoryFailure(LocationFailureKind.unavailable);
    }
  }
}

class GeolocatorGateway implements LocationPlatformGateway {
  const GeolocatorGateway();

  @override
  Future<PlatformLocationPermission> checkPermission() async {
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<PlatformPosition> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return PlatformPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      altitudeMeters: position.altitude,
      recordedAt: position.timestamp,
    );
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<PlatformLocationPermission> requestPermission() async {
    return _mapPermission(await Geolocator.requestPermission());
  }

  PlatformLocationPermission _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => PlatformLocationPermission.denied,
      LocationPermission.deniedForever =>
        PlatformLocationPermission.deniedForever,
      LocationPermission.whileInUse => PlatformLocationPermission.whileInUse,
      LocationPermission.always => PlatformLocationPermission.always,
    };
  }
}
