import 'dart:async';

import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
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
    required this.locationRepository,
    required this.solarService,
    required this.cache,
    this.wildlifeRepository,
    this.remoteContextRepository,
    this.route = RouteContextState.none,
    this.corridor,
    // GeolocatorRepository tries native AMap first, then a recent system fix,
    // GNSS and Android's balanced network provider. Keep this outer guard
    // above the whole recovery chain so every fallback remains available.
    this.locationTimeout = const Duration(seconds: 21),
    this.logger,
    this.cacheWriteGuard,
    required this.now,
    required this.utcOffset,
  });

  final LocationRepository locationRepository;
  final SolarService solarService;
  final ContextCache cache;
  final WildlifeRepository? wildlifeRepository;
  final RemoteContextRepository? remoteContextRepository;
  final RouteContextState route;
  final RouteCorridorContext? corridor;
  final Duration locationTimeout;
  final AppLogger? logger;
  final ContextCacheWriteGuard? cacheWriteGuard;
  final DateTime Function() now;
  final Duration Function() utcOffset;

  Future<ContextSnapshot>? _inFlight;

  Future<ContextSnapshot> load() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<ContextSnapshot> _load() async {
    final cacheWriteGeneration = cacheWriteGuard?.begin();
    final remoteRepository = remoteContextRepository;
    if (remoteRepository == null) {
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
    try {
      var snapshot = await remoteRepository
          .fetchSnapshot(
            location: location,
            observedAt: generatedAt,
            route: route,
            corridor: corridor,
          )
          .timeout(const Duration(seconds: 3));
      final solar = solarService.calculate(
        point: location.point,
        moment: generatedAt,
        utcOffset: utcOffset(),
        altitudeMeters: location.altitudeMeters ?? 0,
      );
      snapshot = snapshot.withSolarReference(
        elevationDegrees: solar.elevationDegrees,
        azimuthDegrees: solar.azimuthDegrees,
        sunrise: solar.sunrise,
        sunset: solar.sunset,
      );
      final wildlifeActivity = await wildlifeFuture;
      if (wildlifeActivity?.hasActivity == true) {
        snapshot = snapshot.withWildlifeActivity(wildlifeActivity!);
      }
      await _writeCache(snapshot, cacheWriteGeneration);
      return snapshot;
    } catch (error) {
      final remoteFailure = switch (error) {
        RemoteContextFailure() => error,
        TimeoutException() => const RemoteContextFailure(
          RemoteContextFailureKind.network,
        ),
        _ => const RemoteContextFailure(RemoteContextFailureKind.response),
      };
      logger?.warning(
        LogCategory.degradation,
        'broker.snapshot_failed',
        data: {LogDataKey.reason: remoteFailure.kind.name},
      );
      return _cachedOrThrow(EnvironmentFailureKind.weather, remoteFailure);
    }
  }

  Future<void> _writeCache(
    ContextSnapshot snapshot,
    int? cacheWriteGeneration,
  ) async {
    final guard = cacheWriteGuard;
    if (guard != null &&
        cacheWriteGeneration != null &&
        !guard.allows(cacheWriteGeneration)) {
      return;
    }
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
