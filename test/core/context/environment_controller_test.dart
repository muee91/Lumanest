import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/infrastructure/solar/nrel_solar_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 10);
  final location = LocationReading(
    point: const GeoPoint(latitude: 30.25, longitude: 120.15),
    recordedAt: now,
    accuracyMeters: 8,
  );

  EnvironmentLoader loader({
    LocationRepository? locations,
    RemoteContextRepository? remote,
    ContextCache? cache,
    RouteContextState route = RouteContextState.none,
  }) => EnvironmentLoader(
    locationRepository: locations ?? _Location(location),
    solarService: NrelSolarService(),
    cache: cache ?? InMemoryContextCache(),
    remoteContextRepository: remote,
    route: route,
    now: () => now,
    utcOffset: () => const Duration(hours: 8),
  );

  test('default location timeout covers the complete acquisition chain', () {
    expect(
      loader(remote: _Remote(ContextFixtures.lakeSunset())).locationTimeout,
      const Duration(seconds: 21),
    );
  });

  test('loads the current Broker snapshot and writes it to cache', () async {
    final cache = InMemoryContextCache();
    final result = await loader(
      remote: _Remote(ContextFixtures.lakeSunset(observedAt: now)),
      cache: cache,
    ).load();

    expect(result.primaryScene, SceneType.lake);
    expect(result.solarElevationDegrees, isNotNull);
    expect((await cache.readLatest())?.id, result.id);
  });

  test(
    'missing Broker configuration fails before requesting location',
    () async {
      final locations = _Location(location);
      await expectLater(
        loader(locations: locations).load(),
        throwsA(
          isA<EnvironmentLoadFailure>().having(
            (error) => error.kind,
            'kind',
            EnvironmentFailureKind.configMissing,
          ),
        ),
      );
      expect(locations.calls, 0);
    },
  );

  test('location failure restores only a stale current cache', () async {
    final cache = InMemoryContextCache();
    await cache.write(
      ContextFixtures.quietCity(observedAt: now.subtract(const Duration(hours: 1))),
    );

    final result = await loader(
      locations: _FailingLocation(),
      remote: _Remote(ContextFixtures.lakeSunset()),
      cache: cache,
    ).load();

    expect(result.isStale, isTrue);
  });

  test(
    'Broker failure restores stale cache and never builds local facts',
    () async {
      final cache = InMemoryContextCache();
      await cache.write(
        ContextFixtures.quietCity(observedAt: now.subtract(const Duration(hours: 1))),
      );

      final result = await loader(
        remote: _Remote.failure(),
        cache: cache,
      ).load();

      expect(result.isStale, isTrue);
      expect(result.id, ContextFixtures.quietCity().id);
    },
  );

  test('Broker failure without cache remains a weather failure', () async {
    await expectLater(
      loader(remote: _Remote.failure()).load(),
      throwsA(
        isA<EnvironmentLoadFailure>().having(
          (error) => error.kind,
          'kind',
          EnvironmentFailureKind.weather,
        ),
      ),
    );
  });

  test('deduplicates simultaneous refresh requests', () async {
    final remote = _Remote(ContextFixtures.lakeSunset(observedAt: now));
    final value = loader(remote: remote);

    await Future.wait([value.load(), value.load(), value.load()]);

    expect(remote.calls, 1);
  });

  test('forwards the current route state to the Broker', () async {
    final remote = _Remote(ContextFixtures.lakeSunset(observedAt: now));
    await loader(
      remote: remote,
      route: RouteContextState.active(ContextRouteMode.driving),
    ).load();

    expect(remote.route?.stage, ContextRouteStage.active);
  });
}

class _Location implements LocationRepository {
  _Location(this.value);
  final LocationReading value;
  int calls = 0;

  @override
  Future<LocationReading> current() async {
    calls += 1;
    return value;
  }
}

class _FailingLocation implements LocationRepository {
  @override
  Future<LocationReading> current() => Future.error(StateError('unavailable'));
}

class _Remote implements RemoteContextRepository {
  _Remote(this.value) : error = null;
  _Remote.failure()
    : value = null,
      error = const RemoteContextFailure(RemoteContextFailureKind.network);

  final ContextSnapshot? value;
  final Object? error;
  int calls = 0;
  RouteContextState? route;

  @override
  Future<ContextSnapshot> fetchSnapshot({
    required LocationReading location,
    required DateTime observedAt,
    RouteContextState route = RouteContextState.none,
    corridor,
  }) async {
    calls += 1;
    this.route = route;
    if (error != null) throw error!;
    return value!;
  }
}
