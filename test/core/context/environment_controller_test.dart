import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';
import 'package:luma_nest/src/infrastructure/location/geolocator_repository.dart';

void main() {
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

  EnvironmentLoader createLoader({bool configured = true}) {
    return EnvironmentLoader(
      qweatherConfigured: configured,
      locationRepository: location,
      weatherRepository: weather,
      solarService: solar,
      snapshotBuilder: const ContextSnapshotBuilder(),
      cache: cache,
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

  test('preserves sanitized location failure category for recovery UI', () async {
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
  });

  test('returns a stale cached snapshot when weather refresh fails', () async {
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
    weather.error = StateError('offline');

    final snapshot = await createLoader().load();

    expect(snapshot.id, 'cached');
    expect(snapshot.isStale, isTrue);
    expect(snapshot.observedAt, cached.observedAt);
  });

  test('Riverpod controller exposes the loader result', () async {
    final container = ProviderContainer(
      overrides: [environmentLoaderProvider.overrideWithValue(createLoader())],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(environmentSnapshotProvider.future);

    expect(snapshot.location?.latitude, 31.2304);
  });
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

class _FakeWeatherRepository implements WeatherRepository {
  _FakeWeatherRepository(this.value);

  final WeatherObservation value;
  Object? error;
  int calls = 0;

  @override
  Future<WeatherObservation> fetchCurrent(GeoPoint point) async {
    calls += 1;
    if (error case final error?) throw error;
    return value;
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
