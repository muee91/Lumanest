import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/infrastructure/location/geolocator_repository.dart';

void main() {
  late _FakeLocationGateway gateway;
  late GeolocatorRepository repository;

  setUp(() {
    gateway = _FakeLocationGateway();
    repository = GeolocatorRepository(gateway);
  });

  test('reports disabled location services', () async {
    gateway.serviceEnabled = false;

    await expectLater(
      repository.current,
      throwsA(
        isA<LocationRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          LocationFailureKind.serviceDisabled,
        ),
      ),
    );
  });

  test('requests permission once then reports denial', () async {
    gateway.permission = PlatformLocationPermission.denied;
    gateway.requestedPermission = PlatformLocationPermission.denied;

    await expectLater(
      repository.current,
      throwsA(
        isA<LocationRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          LocationFailureKind.permissionDenied,
        ),
      ),
    );
    expect(gateway.requestCount, 1);
  });

  test(
    'reports permanently denied permission without requesting again',
    () async {
      gateway.permission = PlatformLocationPermission.deniedForever;

      await expectLater(
        repository.current,
        throwsA(
          isA<LocationRepositoryFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocationFailureKind.permissionDeniedForever,
          ),
        ),
      );
      expect(gateway.requestCount, 0);
    },
  );

  test('returns a WGS84 reading after permission is granted', () async {
    gateway.permission = PlatformLocationPermission.whileInUse;
    gateway.position = PlatformPosition(
      latitude: 31.2304,
      longitude: 121.4737,
      accuracyMeters: 6,
      altitudeMeters: 14,
      recordedAt: DateTime.utc(2026, 7, 11, 12),
    );

    final reading = await repository.current();

    expect(reading.point.latitude, 31.2304);
    expect(reading.point.longitude, 121.4737);
    expect(reading.accuracyMeters, 6);
    expect(reading.recordedAt, DateTime.utc(2026, 7, 11, 12));
  });

  test(
    'turns an unresponsive platform request into a recoverable failure',
    () async {
      gateway.permission = PlatformLocationPermission.whileInUse;
      gateway.positionFuture = Future<PlatformPosition>.delayed(
        const Duration(milliseconds: 30),
        () => PlatformPosition(
          latitude: 31.2304,
          longitude: 121.4737,
          accuracyMeters: 6,
          altitudeMeters: 14,
          recordedAt: DateTime.utc(2026, 7, 11, 12),
        ),
      );
      repository = GeolocatorRepository(
        gateway,
        positionTimeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        repository.current(),
        throwsA(
          isA<LocationRepositoryFailure>().having(
            (failure) => failure.kind,
            'kind',
            LocationFailureKind.unavailable,
          ),
        ),
      );
    },
  );
}

class _FakeLocationGateway implements LocationPlatformGateway {
  bool serviceEnabled = true;
  PlatformLocationPermission permission = PlatformLocationPermission.denied;
  PlatformLocationPermission requestedPermission =
      PlatformLocationPermission.denied;
  int requestCount = 0;
  late PlatformPosition position;
  Future<PlatformPosition>? positionFuture;

  @override
  Future<PlatformLocationPermission> checkPermission() async => permission;

  @override
  Future<PlatformPosition> getCurrentPosition() async =>
      positionFuture ?? position;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<PlatformLocationPermission> requestPermission() async {
    requestCount += 1;
    return requestedPermission;
  }
}
