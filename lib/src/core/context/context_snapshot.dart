import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';

enum SceneType { unknown, city, lake, mountain, desert, village }

enum DayPhase { dawn, day, sunset, blueHour, night }

enum WeatherType { clear, cloudy, rain, snow, dust, unknown }

enum ContextDataFreshness { fresh, stale }

enum MoonPhase {
  newMoon,
  waxingCrescent,
  firstQuarter,
  waxingGibbous,
  fullMoon,
  waningGibbous,
  lastQuarter,
  waningCrescent,
}

enum ContextRouteMode { none, driving, hiking }

enum ContextRouteStage { none, planned, active, paused }

enum AstronomyGeometryStatus { geometryOnly, unavailable }

class GalacticCenterWindow {
  const GalacticCenterWindow({
    required this.startAt,
    required this.peakAt,
    required this.endAt,
    required this.peakAltitudeDegrees,
  });

  final DateTime startAt;
  final DateTime peakAt;
  final DateTime endAt;
  final double peakAltitudeDegrees;
}

/// Deterministic celestial geometry from the Context service.
///
/// This deliberately excludes light pollution, local horizon, access and
/// reviewed shooting-place evidence, so it cannot by itself represent a
/// Milky Way opportunity.
class AstronomyGeometry {
  const AstronomyGeometry({
    required this.status,
    this.astronomicalNight,
    this.moonAltitudeDegrees,
    this.moonAzimuthDegrees,
    this.moonriseAt,
    this.moonsetAt,
    this.moonPhase,
    this.moonIllumination,
    this.galacticCenterAltitudeDegrees,
    this.galacticCenterAzimuthDegrees,
    this.galacticCenterWindow,
  });

  final AstronomyGeometryStatus status;
  final bool? astronomicalNight;
  final double? moonAltitudeDegrees;
  final double? moonAzimuthDegrees;
  final DateTime? moonriseAt;
  final DateTime? moonsetAt;
  final MoonPhase? moonPhase;
  final double? moonIllumination;
  final double? galacticCenterAltitudeDegrees;
  final double? galacticCenterAzimuthDegrees;
  final GalacticCenterWindow? galacticCenterWindow;

  bool get hasGeometry => status == AstronomyGeometryStatus.geometryOnly;
}

class ContextSnapshot {
  ContextSnapshot({
    required this.id,
    required this.observedAt,
    required this.expiresAt,
    required this.primaryScene,
    this.sceneContext,
    required this.dayPhase,
    required this.weather,
    required this.activeRoute,
    List<String> opportunityIds = const [],
    List<String> safetyEventIds = const [],
    List<String> wildlifeEventIds = const [],
    List<ContextEvent> events = const [],
    List<ShootingSession> shootingSessions = const [],
    this.wildlifeActivity,
    this.location,
    this.temperatureCelsius,
    this.windSpeedMetersPerSecond,
    this.windDirectionDegrees,
    this.visibilityKilometers,
    this.precipitationMillimeters,
    this.cloudCoverPercent,
    this.airQualityIndex,
    this.airQualityCategory,
    this.primaryPollutant,
    this.airQualityObservedAt,
    this.airQualityStale = true,
    this.solarElevationDegrees,
    this.solarAzimuthDegrees,
    this.sunrise,
    this.sunset,
    this.isStale = false,
    this.remoteGeneratedAt,
    this.dataFreshness = ContextDataFreshness.fresh,
    this.moonPhase,
    this.moonIllumination,
    this.astronomyGeometry,
    this.routeMode = ContextRouteMode.none,
    this.routeStage = ContextRouteStage.none,
    List<ContextAction> allowedActions = const [],
    this.serverManifest,
    List<ContextEntry> entries = const [],
    this.canonicalEntriesPresent = false,
  }) : opportunityIds = List.unmodifiable(opportunityIds),
       safetyEventIds = List.unmodifiable(safetyEventIds),
       wildlifeEventIds = List.unmodifiable(wildlifeEventIds),
       events = List.unmodifiable(events),
       shootingSessions = List.unmodifiable(shootingSessions),
       entries = List.unmodifiable(entries),
       allowedActions = List.unmodifiable(allowedActions);

  final String id;
  final DateTime observedAt;
  final DateTime expiresAt;
  final SceneType primaryScene;
  final SceneContext? sceneContext;
  final DayPhase dayPhase;
  final WeatherType weather;
  final bool activeRoute;
  final List<String> opportunityIds;
  final List<String> safetyEventIds;
  final List<String> wildlifeEventIds;
  final List<ContextEvent> events;

  /// Explainable, non-probabilistic shooting sessions in the current contract.
  final List<ShootingSession> shootingSessions;
  final RegionalWildlifeActivity? wildlifeActivity;
  final GeoPoint? location;
  final double? temperatureCelsius;
  final double? windSpeedMetersPerSecond;
  final double? windDirectionDegrees;
  final double? visibilityKilometers;
  final double? precipitationMillimeters;
  final double? cloudCoverPercent;
  final int? airQualityIndex;
  final String? airQualityCategory;
  final String? primaryPollutant;
  final DateTime? airQualityObservedAt;
  final bool airQualityStale;
  final double? solarElevationDegrees;
  final double? solarAzimuthDegrees;
  final DateTime? sunrise;
  final DateTime? sunset;
  final bool isStale;
  final DateTime? remoteGeneratedAt;
  final ContextDataFreshness dataFreshness;
  final MoonPhase? moonPhase;
  final double? moonIllumination;
  final AstronomyGeometry? astronomyGeometry;
  final ContextRouteMode routeMode;
  final ContextRouteStage routeStage;
  final List<ContextAction> allowedActions;
  final ServerManifest? serverManifest;
  final List<ContextEntry> entries;
  final bool canonicalEntriesPresent;

  /// Composite scene state used by the v5 cache and catalog engine. Local
  /// deterministic snapshots derive it from [primaryScene] when necessary.
  SceneContext get resolvedSceneContext =>
      sceneContext ?? _sceneContextFromPrimaryScene(primaryScene);

  ContextSnapshot asStale() {
    final retainedEvents = events
        .where((event) => event.channel != ContextEventChannel.opportunity)
        .toList(growable: false);
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: primaryScene,
      sceneContext: sceneContext,
      dayPhase: dayPhase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: const [],
      safetyEventIds: safetyEventIds,
      wildlifeEventIds: wildlifeEventIds,
      events: retainedEvents,
      shootingSessions: const [],
      wildlifeActivity: wildlifeActivity,
      location: location,
      temperatureCelsius: temperatureCelsius,
      windSpeedMetersPerSecond: windSpeedMetersPerSecond,
      windDirectionDegrees: windDirectionDegrees,
      visibilityKilometers: visibilityKilometers,
      precipitationMillimeters: precipitationMillimeters,
      cloudCoverPercent: cloudCoverPercent,
      airQualityIndex: airQualityIndex,
      airQualityCategory: airQualityCategory,
      primaryPollutant: primaryPollutant,
      airQualityObservedAt: airQualityObservedAt,
      airQualityStale: true,
      solarElevationDegrees: solarElevationDegrees,
      solarAzimuthDegrees: solarAzimuthDegrees,
      sunrise: sunrise,
      sunset: sunset,
      isStale: true,
      remoteGeneratedAt: remoteGeneratedAt,
      dataFreshness: ContextDataFreshness.stale,
      moonPhase: moonPhase,
      moonIllumination: moonIllumination,
      astronomyGeometry: astronomyGeometry,
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: retainedEvents
          .map((event) => event.allowedAction)
          .whereType<ContextAction>()
          .toSet()
          .toList(growable: false),
      serverManifest: serverManifest,
      entries: entries,
      canonicalEntriesPresent: canonicalEntriesPresent,
    );
  }

  ContextSnapshot withWildlifeActivity(RegionalWildlifeActivity activity) {
    final wildlifeEvents = activity.hasActivity
        ? [
            ContextEvent(
              id: 'regional-wildlife',
              channel: ContextEventChannel.wildlifeOpportunity,
              source: ContextEventSource.wildlifeHistorical,
              observedAt: observedAt,
              expiresAt: expiresAt,
              confidence: (activity.occurrenceSampleSize / 20).clamp(0.25, 0.8),
            ),
          ]
        : const <ContextEvent>[];
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: primaryScene,
      sceneContext: sceneContext,
      dayPhase: dayPhase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: opportunityIds,
      safetyEventIds: safetyEventIds,
      wildlifeEventIds: activity.hasActivity
          ? const ['regional-wildlife']
          : const [],
      events: [
        ...events.where(
          (event) => event.channel != ContextEventChannel.wildlifeOpportunity,
        ),
        ...wildlifeEvents,
      ],
      shootingSessions: shootingSessions,
      wildlifeActivity: activity,
      location: location,
      temperatureCelsius: temperatureCelsius,
      windSpeedMetersPerSecond: windSpeedMetersPerSecond,
      windDirectionDegrees: windDirectionDegrees,
      visibilityKilometers: visibilityKilometers,
      precipitationMillimeters: precipitationMillimeters,
      cloudCoverPercent: cloudCoverPercent,
      airQualityIndex: airQualityIndex,
      airQualityCategory: airQualityCategory,
      primaryPollutant: primaryPollutant,
      airQualityObservedAt: airQualityObservedAt,
      airQualityStale: airQualityStale,
      solarElevationDegrees: solarElevationDegrees,
      solarAzimuthDegrees: solarAzimuthDegrees,
      sunrise: sunrise,
      sunset: sunset,
      isStale: isStale || dataFreshness == ContextDataFreshness.stale,
      remoteGeneratedAt: remoteGeneratedAt,
      dataFreshness: dataFreshness,
      moonPhase: moonPhase,
      moonIllumination: moonIllumination,
      astronomyGeometry: astronomyGeometry,
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: allowedActions,
      serverManifest: serverManifest,
      entries: entries,
      canonicalEntriesPresent: canonicalEntriesPresent,
    );
  }

  ContextSnapshot withSolarReference({
    required double elevationDegrees,
    required double azimuthDegrees,
    required DateTime? sunrise,
    required DateTime? sunset,
  }) {
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: primaryScene,
      sceneContext: sceneContext,
      dayPhase: dayPhase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: opportunityIds,
      safetyEventIds: safetyEventIds,
      wildlifeEventIds: wildlifeEventIds,
      events: events,
      shootingSessions: shootingSessions,
      wildlifeActivity: wildlifeActivity,
      location: location,
      temperatureCelsius: temperatureCelsius,
      windSpeedMetersPerSecond: windSpeedMetersPerSecond,
      windDirectionDegrees: windDirectionDegrees,
      visibilityKilometers: visibilityKilometers,
      precipitationMillimeters: precipitationMillimeters,
      cloudCoverPercent: cloudCoverPercent,
      airQualityIndex: airQualityIndex,
      airQualityCategory: airQualityCategory,
      primaryPollutant: primaryPollutant,
      airQualityObservedAt: airQualityObservedAt,
      airQualityStale: airQualityStale,
      solarElevationDegrees: elevationDegrees,
      solarAzimuthDegrees: azimuthDegrees,
      sunrise: sunrise,
      sunset: sunset,
      isStale: isStale,
      remoteGeneratedAt: remoteGeneratedAt,
      dataFreshness: dataFreshness,
      moonPhase: moonPhase,
      moonIllumination: moonIllumination,
      astronomyGeometry: astronomyGeometry,
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: allowedActions,
      serverManifest: serverManifest,
      entries: entries,
      canonicalEntriesPresent: canonicalEntriesPresent,
    );
  }

  ContextSnapshot withRemoteContext({
    required String id,
    required DateTime expiresAt,
    required SceneType primaryScene,
    SceneContext? sceneContext,
    required List<ContextEvent> events,
    List<ShootingSession> shootingSessions = const [],
    required DateTime remoteGeneratedAt,
    required ContextDataFreshness dataFreshness,
    required MoonPhase moonPhase,
    required double moonIllumination,
    AstronomyGeometry? astronomyGeometry,
    required ContextRouteMode routeMode,
    required ContextRouteStage routeStage,
    required List<ContextAction> allowedActions,
  }) {
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: primaryScene,
      sceneContext: sceneContext,
      dayPhase: dayPhase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: events
          .where((event) => event.channel == ContextEventChannel.opportunity)
          .map((event) => event.id)
          .toList(growable: false),
      safetyEventIds: events
          .where((event) => event.channel == ContextEventChannel.safety)
          .map((event) => event.id)
          .toList(growable: false),
      events: events,
      shootingSessions: shootingSessions,
      wildlifeActivity: wildlifeActivity,
      location: location,
      temperatureCelsius: temperatureCelsius,
      windSpeedMetersPerSecond: windSpeedMetersPerSecond,
      windDirectionDegrees: windDirectionDegrees,
      visibilityKilometers: visibilityKilometers,
      precipitationMillimeters: precipitationMillimeters,
      cloudCoverPercent: cloudCoverPercent,
      airQualityIndex: airQualityIndex,
      airQualityCategory: airQualityCategory,
      primaryPollutant: primaryPollutant,
      airQualityObservedAt: airQualityObservedAt,
      airQualityStale: airQualityStale,
      solarElevationDegrees: solarElevationDegrees,
      solarAzimuthDegrees: solarAzimuthDegrees,
      sunrise: sunrise,
      sunset: sunset,
      isStale: isStale || dataFreshness == ContextDataFreshness.stale,
      remoteGeneratedAt: remoteGeneratedAt,
      dataFreshness: dataFreshness,
      moonPhase: moonPhase,
      moonIllumination: moonIllumination,
      astronomyGeometry: astronomyGeometry ?? this.astronomyGeometry,
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: allowedActions,
      serverManifest: serverManifest,
      entries: entries,
      canonicalEntriesPresent: canonicalEntriesPresent,
    );
  }
}

SceneContext _sceneContextFromPrimaryScene(SceneType scene) {
  return switch (scene) {
    SceneType.city => SceneContext(
      primaryScene: PrimaryScene.urban,
      facets: const {SceneFacet.skyline, SceneFacet.architecture},
      activity: ActivityState.stationary,
    ),
    SceneType.lake => SceneContext(
      primaryScene: PrimaryScene.inlandWater,
      facets: const {SceneFacet.lake, SceneFacet.reflectiveSurface},
      activity: ActivityState.stationary,
    ),
    SceneType.mountain => SceneContext(
      primaryScene: PrimaryScene.mountain,
      facets: const <SceneFacet>{},
      activity: ActivityState.stationary,
    ),
    SceneType.desert => SceneContext(
      primaryScene: PrimaryScene.desert,
      facets: const {SceneFacet.dune, SceneFacet.openHorizon},
      activity: ActivityState.stationary,
    ),
    SceneType.village => SceneContext(
      primaryScene: PrimaryScene.village,
      facets: const {SceneFacet.villageStreet},
      activity: ActivityState.stationary,
    ),
    SceneType.unknown => SceneContext(
      primaryScene: PrimaryScene.unknown,
      facets: const <SceneFacet>{},
      activity: ActivityState.stationary,
    ),
  };
}
