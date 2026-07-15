import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_snapshot_builder.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/context/scene_evidence_repository.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
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
    this.route = RouteContextState.none,
    // GeolocatorRepository tries native AMap first, then a recent system fix,
    // GNSS and Android's balanced network provider. Keep this outer guard
    // above the whole recovery chain so every fallback remains available.
    this.locationTimeout = const Duration(seconds: 21),
    this.weatherTimeout = const Duration(seconds: 10),
    this.logger,
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
  final RouteContextState route;
  final Duration locationTimeout;
  final Duration weatherTimeout;
  final AppLogger? logger;
  final DateTime Function() now;
  final Duration Function() utcOffset;

  Future<ContextSnapshot>? _inFlight;

  Future<ContextSnapshot> load() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<ContextSnapshot> _load() async {
    final remoteRepository = remoteContextRepository;
    if (!qweatherConfigured && remoteRepository == null) {
      throw const EnvironmentLoadFailure(EnvironmentFailureKind.configMissing);
    }

    final LocationReading location;
    try {
      location = await locationRepository.current().timeout(locationTimeout);
    } catch (error) {
      return _cachedOrThrow(EnvironmentFailureKind.location, error);
    }

    final generatedAt = now().toUtc();
    final wildlifeFuture = _fetchWildlifeActivity(location.point);
    RemoteContextFailure? remoteFailure;
    if (remoteRepository != null) {
      try {
        var snapshot = await remoteRepository
            .fetchSnapshot(
              location: location,
              observedAt: generatedAt,
              route: route,
            )
            .timeout(const Duration(seconds: 3));
        final wildlifeActivity = await wildlifeFuture;
        if (wildlifeActivity?.hasActivity == true) {
          snapshot = snapshot.withWildlifeActivity(wildlifeActivity!);
        }
        await _writeCache(snapshot);
        return snapshot;
      } catch (error) {
        remoteFailure = error is RemoteContextFailure
            ? error
            : const RemoteContextFailure(RemoteContextFailureKind.response);
        logger?.warning(
          LogCategory.degradation,
          'broker.snapshot_failed',
          data: {LogDataKey.reason: remoteFailure.kind.name},
        );
      }
    }

    if (!qweatherConfigured) {
      return _cachedOrThrow(
        EnvironmentFailureKind.weather,
        remoteFailure ??
            const RemoteContextFailure(RemoteContextFailureKind.configuration),
      );
    }

    // These client-side lookups remain only as the migration and offline-safe
    // path. Once the Broker accepts the minimal contract they are not called.
    final sceneEvidenceFuture = _fetchSceneEvidence(location.point);

    final WeatherObservation weather;
    try {
      weather = await weatherRepository
          .fetchCurrent(location.point)
          .timeout(weatherTimeout);
    } catch (error) {
      return _cachedOrThrow(EnvironmentFailureKind.weather, error);
    }

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
      route: route,
    );
    if (remoteRepository != null &&
        remoteFailure?.kind == RemoteContextFailureKind.unsupportedContract) {
      try {
        snapshot = await remoteRepository
            .enrich(base: snapshot, weather: weather, solar: solar)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // The local deterministic snapshot remains the offline-safe source.
        logger?.warning(
          LogCategory.degradation,
          'broker.enrichment_failed',
          data: const {LogDataKey.source: 'local'},
        );
      }
    }
    final wildlifeActivity = await wildlifeFuture;
    if (wildlifeActivity?.hasActivity == true) {
      snapshot = snapshot.withWildlifeActivity(wildlifeActivity!);
    }
    await _writeCache(snapshot);
    return snapshot;
  }

  Future<void> _writeCache(ContextSnapshot snapshot) async {
    try {
      await cache.write(snapshot);
      logger?.debug(
        LogCategory.contextCache,
        'cache.updated',
        data: {
          LogDataKey.freshness: snapshot.dataFreshness.name,
          LogDataKey.scene: snapshot.primaryScene.name,
        },
      );
    } on Object {
      // A storage failure must not hide a usable live snapshot. The raw
      // storage exception is deliberately not attached to the record.
      logger?.error(LogCategory.contextCache, 'cache.write_failed');
    }
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
    if (cached != null) {
      logger?.warning(
        LogCategory.contextCache,
        'cache.stale_hit',
        data: {LogDataKey.cache: 'hit', LogDataKey.reason: kind.name},
      );
      return cached.asStale();
    }
    logger?.warning(
      LogCategory.contextCache,
      'cache.miss',
      data: {LogDataKey.cache: 'miss', LogDataKey.reason: kind.name},
    );
    throw EnvironmentLoadFailure(kind, cause: cause);
  }
}
