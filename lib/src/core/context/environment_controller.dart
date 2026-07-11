import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';

enum EnvironmentFailureKind { configMissing, location, weather }

class EnvironmentLoadFailure implements Exception {
  const EnvironmentLoadFailure(this.kind, {this.cause});

  final EnvironmentFailureKind kind;
  /// A typed, sanitized domain failure for recovery UI. Never include it in
  /// string output because adapters may carry transport details.
  final Object? cause;

  @override
  String toString() => 'EnvironmentLoadFailure($kind)';
}

class EnvironmentLoader {
  EnvironmentLoader({
    required this.qweatherConfigured,
    required this.locationRepository,
    required this.weatherRepository,
    required this.solarService,
    required this.snapshotBuilder,
    required this.cache,
    required this.now,
    required this.utcOffset,
  });

  final bool qweatherConfigured;
  final LocationRepository locationRepository;
  final WeatherRepository weatherRepository;
  final SolarService solarService;
  final ContextSnapshotBuilder snapshotBuilder;
  final ContextCache cache;
  final DateTime Function() now;
  final Duration Function() utcOffset;

  Future<ContextSnapshot>? _inFlight;

  Future<ContextSnapshot> load() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<ContextSnapshot> _load() async {
    if (!qweatherConfigured) {
      throw const EnvironmentLoadFailure(EnvironmentFailureKind.configMissing);
    }

    final LocationReading location;
    try {
      location = await locationRepository.current();
    } catch (error) {
      return _cachedOrThrow(EnvironmentFailureKind.location, error);
    }

    final WeatherObservation weather;
    try {
      weather = await weatherRepository.fetchCurrent(location.point);
    } catch (error) {
      return _cachedOrThrow(EnvironmentFailureKind.weather, error);
    }

    final generatedAt = now().toUtc();
    final solar = solarService.calculate(
      point: location.point,
      moment: generatedAt,
      utcOffset: utcOffset(),
      altitudeMeters: location.altitudeMeters ?? 0,
    );
    final snapshot = snapshotBuilder.build(
      location: location,
      weather: weather,
      solar: solar,
      generatedAt: generatedAt,
    );
    await cache.write(snapshot);
    return snapshot;
  }

  Future<ContextSnapshot> _cachedOrThrow(
    EnvironmentFailureKind kind,
    Object cause,
  ) async {
    final cached = await cache.readLatest();
    if (cached != null) return cached.asStale();
    throw EnvironmentLoadFailure(kind, cause: cause);
  }
}
