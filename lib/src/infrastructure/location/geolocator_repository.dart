import 'package:geolocator/geolocator.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/infrastructure/location/amap_location_gateway.dart';

export 'package:luma_nest/src/core/location/location_repository.dart'
    show LocationFailureKind, LocationRepositoryFailure;

enum PlatformLocationPermission { denied, deniedForever, whileInUse, always }

enum PlatformLocationAccuracy { high, balanced }

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

  Future<PlatformPosition?> getLastKnownPosition();

  Future<PlatformPosition> getCurrentPosition(
    PlatformLocationAccuracy accuracy,
  );
}

class GeolocatorRepository implements LocationRepository {
  const GeolocatorRepository(
    this._gateway, {
    this.highAccuracyTimeout = const Duration(seconds: 8),
    this.balancedAccuracyTimeout = const Duration(seconds: 5),
    this.maximumLastKnownAge = const Duration(minutes: 15),
    this.fallbackSettleDelay = const Duration(milliseconds: 300),
    this.amapGateway,
    this.amapTimeout = const Duration(seconds: 6),
  });

  final LocationPlatformGateway _gateway;
  final Duration highAccuracyTimeout;
  final Duration balancedAccuracyTimeout;
  final Duration maximumLastKnownAge;
  final Duration fallbackSettleDelay;
  final AmapLocationGateway? amapGateway;
  final Duration amapTimeout;

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

    // On Android in China, AMap's fused location is the primary source. It
    // combines satellite, Wi-Fi and base-station signals and avoids waiting
    // for a system fused provider that may never publish a fix.
    final amap = await _tryAmapPosition();
    if (amap != null) {
      return LocationReading(
        point: amap.point,
        recordedAt: amap.recordedAt,
        accuracyMeters: amap.accuracyMeters,
        altitudeMeters: amap.altitudeMeters,
      );
    }

    final recent = await _lastKnownPosition();
    if (recent != null) return _readingFrom(recent);

    // Android high accuracy delegates to the system GNSS fusion. On supported
    // hardware this includes BeiDou alongside GPS, Galileo and GLONASS.
    final highAccuracy = await _tryPosition(
      PlatformLocationAccuracy.high,
      highAccuracyTimeout,
    );
    if (highAccuracy != null) return _readingFrom(highAccuracy);

    // The Android plugin cancels its native request asynchronously after its
    // own time limit. Give that cancellation a brief head start before a
    // second request is sent through the same method channel.
    await Future<void>.delayed(fallbackSettleDelay);

    // Indoor, urban canyon and first-fix cases need a second path. Android's
    // balanced request can use Wi-Fi, base-station and network fusion.
    final balanced = await _tryPosition(
      PlatformLocationAccuracy.balanced,
      balancedAccuracyTimeout,
    );
    if (balanced != null) return _readingFrom(balanced);

    throw const LocationRepositoryFailure(LocationFailureKind.unavailable);
  }

  Future<PlatformPosition?> _lastKnownPosition() async {
    try {
      final position = await _gateway.getLastKnownPosition();
      if (position == null) return null;
      final age = DateTime.now().toUtc().difference(
        position.recordedAt.toUtc(),
      );
      return age >= Duration.zero && age <= maximumLastKnownAge
          ? position
          : null;
    } on Object {
      return null;
    }
  }

  Future<PlatformPosition?> _tryPosition(
    PlatformLocationAccuracy accuracy,
    Duration timeout,
  ) async {
    try {
      return await _gateway.getCurrentPosition(accuracy).timeout(timeout);
    } on Object {
      return null;
    }
  }

  Future<AmapLocationFix?> _tryAmapPosition() async {
    final gateway = amapGateway;
    if (gateway == null) return null;
    try {
      return await gateway.getCurrentPosition().timeout(amapTimeout);
    } on Object {
      return null;
    }
  }

  LocationReading _readingFrom(PlatformPosition position) {
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
  }
}

class GeolocatorGateway implements LocationPlatformGateway {
  const GeolocatorGateway();

  @override
  Future<PlatformLocationPermission> checkPermission() async {
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<PlatformPosition> getCurrentPosition(
    PlatformLocationAccuracy accuracy,
  ) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy == PlatformLocationAccuracy.high
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
        timeLimit: accuracy == PlatformLocationAccuracy.high
            // Keep the plugin's own timeout below the repository safety
            // timeout. This lets it cancel the native GNSS request before the
            // balanced network request begins.
            ? const Duration(seconds: 7)
            : const Duration(seconds: 4),
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
  Future<PlatformPosition?> getLastKnownPosition() async {
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return PlatformPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      altitudeMeters: position.altitude,
      recordedAt: position.timestamp,
    );
  }

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
