import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/persistent_context_cache.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/context/scene_evidence_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('default location timeout leaves orchestration margin for fallback', () {
    final now = DateTime.utc(2026, 7, 11, 12);
    final loader = EnvironmentLoader(
      qweatherConfigured: true,
      locationRepository: _FakeLocationRepository(_location(now)),
      weatherRepository: _FakeWeatherRepository(_weather(now)),
      solarService: _FakeSolarService(_solar(now)),
      snapshotBuilder: const ContextSnapshotBuilder(),
      cache: InMemoryContextCache(),
      now: DateTime.now,
      utcOffset: () => Duration.zero,
    );

    expect(loader.locationTimeout, const Duration(seconds: 21));
  });

  late _FakeLocationRepository location;
  late _FakeWeatherRepository weather;
  late _FakeSolarService solar;
  late InMemoryContextCache cache;
  final now = DateTime.utc(2026, 7, 11, 12);

  setUp(() {
    location = _FakeLocationRepository(_location(now));
    weather = _FakeWeatherRepository(_weather(now));
    solar = _FakeSolarService(_solar(now));
    cache = InMemoryContextCache();
  });

  EnvironmentLoader createLoader({
    bool configured = true,
    WildlifeRepository? wildlifeRepository,
    SceneEvidenceRepository? sceneEvidenceRepository,
    RemoteContextRepository? remoteContextRepository,
    Duration locationTimeout = const Duration(seconds: 15),
    Duration weatherTimeout = const Duration(seconds: 10),
    RouteContextState route = RouteContextState.none,
    AppLogger? logger,
    ContextCache? contextCache,
  }) {
    return EnvironmentLoader(
      qweatherConfigured: configured,
      locationRepository: location,
      weatherRepository: weather,
      solarService: solar,
      snapshotBuilder: const ContextSnapshotBuilder(),
      cache: contextCache ?? cache,
      wildlifeRepository: wildlifeRepository,
      sceneEvidenceRepository: sceneEvidenceRepository,
      remoteContextRepository: remoteContextRepository,
      route: route,
      locationTimeout: locationTimeout,
      weatherTimeout: weatherTimeout,
      logger: logger,
      now: () => now,
      utcOffset: () => const Duration(hours: 8),
    );
  }

  test('loads location then weather and solar into a fresh snapshot', () async {
    final snapshot = await createLoader().load();

    expect(location.calls, 1);
    expect(weather.calls, 1);
    expect(solar.calls, 1);
    expect(snapshot.isStale, isFalse);
    expect(await cache.readLatest(), same(snapshot));
  });

  test(
    'cache write failure does not hide a fresh snapshot or raw error',
    () async {
      final records = <LogRecord>[];
      final snapshot = await createLoader(
        contextCache: _FailingWriteContextCache(),
        logger: AppLogger(sink: records.add, now: () => now),
      ).load();

      expect(snapshot.isStale, isFalse);
      expect(
        records.map((record) => record.event),
        contains('cache.write_failed'),
      );
      expect(records.join('\n'), isNot(contains('storage-token-secret')));
    },
  );

  test(
    'uses the minimal Broker snapshot before client weather or solar',
    () async {
      final remote = _FakeRemoteContextRepository(
        snapshot: _remoteSnapshot(now, _location(now).point),
      );

      final snapshot = await createLoader(
        configured: false,
        remoteContextRepository: remote,
      ).load();

      expect(snapshot.id, 'remote');
      expect(remote.fetchCalls, 1);
      expect(remote.enrichCalls, 0);
      expect(weather.calls, 0);
      expect(solar.calls, 0);
    },
  );

  test(
    'retries the legacy contract only when the old Broker rejects minimal input',
    () async {
      final remote = _FakeRemoteContextRepository(
        snapshot: _remoteSnapshot(now, _location(now).point),
        fetchError: const RemoteContextFailure(
          RemoteContextFailureKind.unsupportedContract,
        ),
      );

      final snapshot = await createLoader(
        remoteContextRepository: remote,
      ).load();

      expect(snapshot.id, 'remote');
      expect(remote.fetchCalls, 1);
      expect(remote.enrichCalls, 1);
      expect(weather.calls, 1);
      expect(solar.calls, 1);
    },
  );

  test('does not retry the Broker after a network failure', () async {
    final remote = _FakeRemoteContextRepository(
      snapshot: _remoteSnapshot(now, _location(now).point),
      fetchError: const RemoteContextFailure(RemoteContextFailureKind.network),
    );

    final snapshot = await createLoader(remoteContextRepository: remote).load();

    expect(snapshot.id, startsWith('live-'));
    expect(remote.fetchCalls, 1);
    expect(remote.enrichCalls, 0);
    expect(weather.calls, 1);
  });

  test('loader forwards the route context to the Broker as-is', () async {
    final remote = _FakeRemoteContextRepository(
      snapshot: _remoteSnapshot(now, _location(now).point),
    );
    final route = RouteContextState.active(ContextRouteMode.driving);

    await createLoader(
      configured: false,
      remoteContextRepository: remote,
      route: route,
    ).load();

    expect(remote.fetchCalls, 1);
    expect(remote.recordedRoutes, [route]);
  });

  test('deduplicates simultaneous refresh requests', () async {
    final completer = Completer<LocationReading>();
    location.pending = completer.future;
    final loader = createLoader();

    final first = loader.load();
    final second = loader.load();
    completer.complete(_location(now));

    await Future.wait([first, second]);
    expect(location.calls, 1);
  });

  test(
    'reports missing weather configuration before requesting location',
    () async {
      await expectLater(
        createLoader(configured: false).load(),
        throwsA(
          isA<EnvironmentLoadFailure>().having(
            (failure) => failure.kind,
            'kind',
            EnvironmentFailureKind.configMissing,
          ),
        ),
      );
      expect(location.calls, 0);
    },
  );

  test(
    'preserves sanitized location failure category for recovery UI',
    () async {
      location.error = const LocationRepositoryFailure(
        LocationFailureKind.permissionDeniedForever,
      );

      await expectLater(
        createLoader().load(),
        throwsA(
          isA<EnvironmentLoadFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                EnvironmentFailureKind.location,
              )
              .having(
                (failure) => failure.cause,
                'cause',
                isA<LocationRepositoryFailure>().having(
                  (failure) => failure.kind,
                  'location kind',
                  LocationFailureKind.permissionDeniedForever,
                ),
              ),
        ),
      );
    },
  );

  test('bounds the complete location acquisition chain', () async {
    final neverCompletes = Completer<LocationReading>();
    location.pending = neverCompletes.future;

    await expectLater(
      createLoader(locationTimeout: const Duration(milliseconds: 1)).load(),
      throwsA(
        isA<EnvironmentLoadFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnvironmentFailureKind.location,
        ),
      ),
    );
  });

  test('returns a stale cached snapshot when weather refresh fails', () async {
    final records = <LogRecord>[];
    final logger = AppLogger(sink: records.add, now: () => now);
    final cached = ContextSnapshot(
      id: 'cached',
      observedAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.subtract(const Duration(minutes: 45)),
      primaryScene: SceneType.unknown,
      dayPhase: DayPhase.day,
      weather: WeatherType.cloudy,
      activeRoute: false,
    );
    await cache.write(cached);
    weather.error = StateError('offline with raw-token-secret');

    final snapshot = await createLoader(logger: logger).load();

    expect(snapshot.id, 'cached');
    expect(snapshot.isStale, isTrue);
    expect(snapshot.observedAt, cached.observedAt);
    expect(records.map((record) => record.event), contains('cache.stale_hit'));
    expect(records.join('\n'), isNot(contains('raw-token-secret')));
    expect(records.join('\n'), isNot(contains('31.2304')));
  });

  test(
    'persistent cache survives a new loader instance while offline',
    () async {
      final preferences = SharedPreferencesAsync();
      const storageKey = 'environment-controller-restart-cache';
      final firstLoader = EnvironmentLoader(
        qweatherConfigured: true,
        locationRepository: location,
        weatherRepository: weather,
        solarService: solar,
        snapshotBuilder: const ContextSnapshotBuilder(),
        cache: PersistentContextCache(preferences, storageKey: storageKey),
        now: () => now,
        utcOffset: () => const Duration(hours: 8),
      );
      final live = await firstLoader.load();

      weather.error = StateError('offline after restart');
      final restartedLoader = EnvironmentLoader(
        qweatherConfigured: true,
        locationRepository: location,
        weatherRepository: weather,
        solarService: solar,
        snapshotBuilder: const ContextSnapshotBuilder(),
        cache: PersistentContextCache(preferences, storageKey: storageKey),
        now: () => now.add(const Duration(minutes: 20)),
        utcOffset: () => const Duration(hours: 8),
      );
      final offline = await restartedLoader.load();

      expect(offline.id, live.id);
      expect(offline.isStale, isTrue);
      expect(offline.location?.latitude, live.location?.latitude);
    },
  );

  test('bounds the complete weather acquisition chain', () async {
    final neverCompletes = Completer<WeatherObservation>();
    weather.pending = neverCompletes.future;

    await expectLater(
      createLoader(weatherTimeout: const Duration(milliseconds: 1)).load(),
      throwsA(
        isA<EnvironmentLoadFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnvironmentFailureKind.weather,
        ),
      ),
    );
  });

  test('adds wildlife only as optional creative context', () async {
    final snapshot = await createLoader(
      wildlifeRepository: _FakeWildlifeRepository(hasActivity: true),
    ).load();

    expect(snapshot.wildlifeEventIds, ['regional-wildlife']);
    expect(snapshot.safetyEventIds, isEmpty);
    expect(snapshot.wildlifeActivity?.groups, [WildlifeGroup.mammal]);
  });

  test('keeps weather snapshot available when wildlife lookup fails', () async {
    final snapshot = await createLoader(
      wildlifeRepository: _FakeWildlifeRepository(error: StateError('offline')),
    ).load();

    expect(snapshot.wildlifeEventIds, isEmpty);
    expect(snapshot.isStale, isFalse);
  });

  test('uses optional semantic evidence to classify the live scene', () async {
    final snapshot = await createLoader(
      sceneEvidenceRepository: const _FakeSceneEvidenceRepository(
        SceneEvidence(waterBody: true),
      ),
    ).load();

    expect(snapshot.primaryScene, SceneType.lake);
    expect(snapshot.opportunityIds, contains('reflection'));
  });

  test('keeps environment available when semantic evidence fails', () async {
    final snapshot = await createLoader(
      sceneEvidenceRepository: _FakeSceneEvidenceRepository(
        const SceneEvidence(),
        error: StateError('offline'),
      ),
    ).load();

    expect(snapshot.primaryScene, SceneType.unknown);
    expect(snapshot.isStale, isFalse);
  });

  test('Riverpod controller exposes the loader result', () async {
    final records = <LogRecord>[];
    final container = ProviderContainer(
      overrides: [
        environmentLoaderProvider.overrideWithValue(createLoader()),
        appLoggerProvider.overrideWithValue(
          AppLogger(sink: records.add, now: () => now),
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(environmentSnapshotProvider.future);

    expect(snapshot.location?.latitude, 31.2304);
    expect(records.map((record) => record.event), [
      'context.refresh_started',
      'context.refresh_completed',
    ]);
    expect(records.join('\n'), isNot(contains('31.2304')));
  });

  test(
    'provider keeps a location failure visible instead of retrying itself',
    () async {
      location.error = const LocationRepositoryFailure(
        LocationFailureKind.unavailable,
      );
      final container = ProviderContainer(
        overrides: [
          environmentLoaderProvider.overrideWithValue(createLoader()),
          appLoggerProvider.overrideWithValue(AppLogger(enabled: false)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(environmentSnapshotProvider.future),
        throwsA(isA<EnvironmentLoadFailure>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(container.read(environmentSnapshotProvider).hasError, isTrue);
    },
  );
}

LocationReading _location(DateTime now) => LocationReading(
  point: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
  recordedAt: now,
  accuracyMeters: 8,
);

WeatherObservation _weather(DateTime now) => WeatherObservation(
  observedAt: now,
  temperatureCelsius: 26,
  condition: WeatherCondition.clear,
  windSpeedMetersPerSecond: 2,
  windDirectionDegrees: 180,
  visibilityKilometers: 20,
  precipitationMillimeters: 0,
);

SolarState _solar(DateTime now) => SolarState(
  observedAt: now,
  elevationDegrees: 30,
  azimuthDegrees: 200,
  sunrise: now.subtract(const Duration(hours: 6)),
  sunset: now.add(const Duration(hours: 6)),
  dayPhase: DayPhase.day,
);

ContextSnapshot _remoteSnapshot(DateTime now, GeoPoint location) =>
    ContextSnapshot(
      id: 'remote',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
      location: location,
      remoteGeneratedAt: now,
    );

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository(this.value);

  final LocationReading value;
  Future<LocationReading>? pending;
  Object? error;
  int calls = 0;

  @override
  Future<LocationReading> current() {
    calls += 1;
    if (error case final error?) return Future.error(error);
    return pending ?? Future.value(value);
  }
}

class _FailingWriteContextCache implements ContextCache {
  @override
  Future<void> clear() async {}

  @override
  Future<ContextSnapshot?> readLatest() async => null;

  @override
  Future<void> write(ContextSnapshot snapshot) {
    throw StateError('storage-token-secret');
  }
}

class _FakeWeatherRepository implements WeatherRepository {
  _FakeWeatherRepository(this.value);

  final WeatherObservation value;
  Object? error;
  Future<WeatherObservation>? pending;
  int calls = 0;

  @override
  Future<WeatherObservation> fetchCurrent(GeoPoint point) async {
    calls += 1;
    if (error case final error?) throw error;
    return pending ?? value;
  }
}

class _FakeSolarService implements SolarService {
  _FakeSolarService(this.value);

  final SolarState value;
  int calls = 0;

  @override
  SolarState calculate({
    required GeoPoint point,
    required DateTime moment,
    required Duration utcOffset,
    double altitudeMeters = 0,
  }) {
    calls += 1;
    return value;
  }
}

class _FakeWildlifeRepository implements WildlifeRepository {
  _FakeWildlifeRepository({this.hasActivity = false, this.error});

  final bool hasActivity;
  final Object? error;

  @override
  Future<RegionalWildlifeActivity> fetchRegionalWildlifeActivity(
    GeoPoint location,
  ) async {
    if (error case final failure?) throw failure;
    return RegionalWildlifeActivity(
      radiusKilometers: 20,
      occurrenceSampleSize: hasActivity ? 1 : 0,
      taxa: hasActivity
          ? const [
              WildlifeTaxon(
                scientificName: 'Lutra lutra',
                group: WildlifeGroup.mammal,
                records: 1,
              ),
            ]
          : const [],
    );
  }
}

class _FakeSceneEvidenceRepository implements SceneEvidenceRepository {
  const _FakeSceneEvidenceRepository(this.evidence, {this.error});
  final SceneEvidence evidence;
  final Object? error;

  @override
  Future<SceneEvidence> fetch(GeoPoint location) async {
    if (error case final failure?) throw failure;
    return evidence;
  }
}

class _FakeRemoteContextRepository implements RemoteContextRepository {
  _FakeRemoteContextRepository({required this.snapshot, this.fetchError});

  final ContextSnapshot snapshot;
  final Object? fetchError;
  int fetchCalls = 0;
  int enrichCalls = 0;
  List<RouteContextState> recordedRoutes = [];

  @override
  Future<ContextSnapshot> fetchSnapshot({
    required LocationReading location,
    required DateTime observedAt,
    RouteContextState route = RouteContextState.none,
  }) async {
    fetchCalls += 1;
    recordedRoutes.add(route);
    if (fetchError case final error?) throw error;
    return snapshot;
  }

  @override
  Future<ContextSnapshot> enrich({
    required ContextSnapshot base,
    required WeatherObservation weather,
    required SolarState solar,
  }) async {
    enrichCalls += 1;
    return snapshot;
  }
}
