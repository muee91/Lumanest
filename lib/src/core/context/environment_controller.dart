import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/context/scene_evidence_repository.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';

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
    this.wildlifeRepository,
    this.sceneEvidenceRepository,
    this.remoteContextRepository,
    // GeolocatorRepository tries native AMap first, then a recent system fix,
    // GNSS and Android's balanced network provider. Keep this outer guard
    // above the whole recovery chain so every fallback remains available.
    this.locationTimeout = const Duration(seconds: 21),
    this.weatherTimeout = const Duration(seconds: 10),
    required this.now,
    required this.utcOffset,
  });

  final bool qweatherConfigured;
  final LocationRepository locationRepository;
  final WeatherRepository weatherRepository;
  final SolarService solarService;
  final ContextSnapshotBuilder snapshotBuilder;
  final ContextCache cache;
  final WildlifeRepository? wildlifeRepository;
  final SceneEvidenceRepository? sceneEvidenceRepository;
  final RemoteContextRepository? remoteContextRepository;
  final Duration locationTimeout;
  final Duration weatherTimeout;
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
      location = await locationRepository.current().timeout(locationTimeout);
    } catch (error) {
      return _cachedOrThrow(EnvironmentFailureKind.location, error);
    }

    // Optional context lookups start as soon as a location is available and
    // run beside weather. Their failures never block the base environment.
    final sceneEvidenceFuture = _fetchSceneEvidence(location.point);
    final wildlifeFuture = _fetchWildlifeActivity(location.point);

    final WeatherObservation weather;
    try {
      weather = await weatherRepository
          .fetchCurrent(location.point)
          .timeout(weatherTimeout);
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
    final sceneEvidence = await sceneEvidenceFuture;
    var snapshot = snapshotBuilder.build(
      location: location,
      weather: weather,
      solar: solar,
      generatedAt: generatedAt,
      sceneEvidence: sceneEvidence,
    );
    final remoteRepository = remoteContextRepository;
    if (remoteRepository != null) {
      try {
        snapshot = await remoteRepository
            .enrich(base: snapshot, weather: weather, solar: solar)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // The local deterministic snapshot remains the offline-safe source.
      }
    }
    final wildlifeActivity = await wildlifeFuture;
    if (wildlifeActivity?.hasActivity == true) {
      snapshot = snapshot.withWildlifeActivity(wildlifeActivity!);
    }
    await cache.write(snapshot);
    return snapshot;
  }

  Future<SceneEvidence> _fetchSceneEvidence(GeoPoint location) async {
    final repository = sceneEvidenceRepository;
    if (repository == null) return const SceneEvidence();
    try {
      return await repository
          .fetch(location)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return const SceneEvidence();
    }
  }

  Future<RegionalWildlifeActivity?> _fetchWildlifeActivity(
    GeoPoint location,
  ) async {
    final repository = wildlifeRepository;
    if (repository == null) return null;
    try {
      return await repository
          .fetchRegionalWildlifeActivity(location)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Public historical records are optional creative context. A timeout or
      // upstream failure must never delay the safety or weather snapshot.
      return null;
    }
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
