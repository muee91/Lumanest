import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/location/amap_location_gateway.dart';
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

  test('returns a WGS84 system reading when AMap is unavailable', () async {
    gateway.permission = PlatformLocationPermission.whileInUse;
    gateway.positions[PlatformLocationAccuracy.high] = PlatformPosition(
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
    'falls back to balanced network location after GNSS does not respond',
    () async {
      gateway.permission = PlatformLocationPermission.whileInUse;
      gateway.positionFutures[PlatformLocationAccuracy.high] =
          Future<PlatformPosition>.delayed(
            const Duration(milliseconds: 30),
            () => PlatformPosition(
              latitude: 31.2304,
              longitude: 121.4737,
              accuracyMeters: 6,
              altitudeMeters: 14,
              recordedAt: DateTime.utc(2026, 7, 11, 12),
            ),
          );
      gateway.positions[PlatformLocationAccuracy.balanced] = PlatformPosition(
        latitude: 31.2304,
        longitude: 121.4737,
        accuracyMeters: 250,
        altitudeMeters: 14,
        recordedAt: DateTime.utc(2026, 7, 11, 12),
      );
      repository = GeolocatorRepository(
        gateway,
        highAccuracyTimeout: const Duration(milliseconds: 1),
        fallbackSettleDelay: Duration.zero,
      );

      final reading = await repository.current();

      expect(reading.accuracyMeters, 250);
      expect(gateway.requestedAccuracies, [
        PlatformLocationAccuracy.high,
        PlatformLocationAccuracy.balanced,
      ]);
    },
  );

  test('uses a recent system location when AMap is unavailable', () async {
    gateway.permission = PlatformLocationPermission.whileInUse;
    gateway.lastKnownPosition = PlatformPosition(
      latitude: 31.2304,
      longitude: 121.4737,
      accuracyMeters: 80,
      altitudeMeters: 14,
      recordedAt: DateTime.now().toUtc(),
    );

    final reading = await repository.current();

    expect(reading.accuracyMeters, 80);
    expect(gateway.requestedAccuracies, isEmpty);
  });

  test('uses native AMap before requesting any system position', () async {
    gateway.permission = PlatformLocationPermission.whileInUse;
    final amap = _FakeAmapLocationGateway(
      AmapLocationFix(
        point: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
        accuracyMeters: 95,
        altitudeMeters: 14,
        recordedAt: DateTime.utc(2026, 7, 11, 12),
      ),
    );
    repository = GeolocatorRepository(
      gateway,
      highAccuracyTimeout: const Duration(milliseconds: 1),
      balancedAccuracyTimeout: const Duration(milliseconds: 1),
      fallbackSettleDelay: Duration.zero,
      amapGateway: amap,
    );

    final reading = await repository.current();

    expect(amap.calls, 1);
    expect(gateway.lastKnownCalls, 0);
    expect(gateway.requestedAccuracies, isEmpty);
    expect(reading.point.coordinateSystem, CoordinateSystem.wgs84);
    expect(reading.accuracyMeters, 95);
  });

  test(
    'falls back through recent, high and balanced after AMap fails',
    () async {
      gateway.permission = PlatformLocationPermission.whileInUse;
      final amap = _FakeAmapLocationGateway(null);
      gateway.positions[PlatformLocationAccuracy.balanced] = PlatformPosition(
        latitude: 31.2304,
        longitude: 121.4737,
        accuracyMeters: 180,
        altitudeMeters: 14,
        recordedAt: DateTime.utc(2026, 7, 11, 12),
      );
      repository = GeolocatorRepository(
        gateway,
        amapGateway: amap,
        highAccuracyTimeout: const Duration(milliseconds: 1),
        balancedAccuracyTimeout: const Duration(milliseconds: 10),
        fallbackSettleDelay: Duration.zero,
      );

      final reading = await repository.current();

      expect(amap.calls, 1);
      expect(gateway.lastKnownCalls, 1);
      expect(gateway.requestedAccuracies, [
        PlatformLocationAccuracy.high,
        PlatformLocationAccuracy.balanced,
      ]);
      expect(reading.accuracyMeters, 180);
    },
  );

  test('keeps time for the balanced network fallback by default', () {
    expect(repository.highAccuracyTimeout, const Duration(seconds: 8));
    expect(repository.balancedAccuracyTimeout, const Duration(seconds: 5));
    expect(repository.fallbackSettleDelay, const Duration(milliseconds: 300));
  });
}

class _FakeAmapLocationGateway implements AmapLocationGateway {
  _FakeAmapLocationGateway(this.value);

  final AmapLocationFix? value;
  var calls = 0;

  @override
  Future<AmapLocationFix?> getCurrentPosition() async {
    calls += 1;
    return value;
  }
}

class _FakeLocationGateway implements LocationPlatformGateway {
  bool serviceEnabled = true;
  PlatformLocationPermission permission = PlatformLocationPermission.denied;
  PlatformLocationPermission requestedPermission =
      PlatformLocationPermission.denied;
  int requestCount = 0;
  final positions = <PlatformLocationAccuracy, PlatformPosition>{};
  final positionFutures =
      <PlatformLocationAccuracy, Future<PlatformPosition>>{};
  final requestedAccuracies = <PlatformLocationAccuracy>[];
  PlatformPosition? lastKnownPosition;
  int lastKnownCalls = 0;

  @override
  Future<PlatformLocationPermission> checkPermission() async => permission;

  @override
  Future<PlatformPosition> getCurrentPosition(
    PlatformLocationAccuracy accuracy,
  ) async {
    requestedAccuracies.add(accuracy);
    return positionFutures[accuracy] ?? positions[accuracy]!;
  }

  @override
  Future<PlatformPosition?> getLastKnownPosition() async {
    lastKnownCalls += 1;
    return lastKnownPosition;
  }

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<PlatformLocationPermission> requestPermission() async {
    requestCount += 1;
    return requestedPermission;
  }
}
