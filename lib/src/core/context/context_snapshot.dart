import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';

enum SceneType {
  unknown,
  city,
  lake,
  mountain,
  desert,
  village,
  driving,
  hiking,
}

enum DayPhase { dawn, day, sunset, blueHour, night }

enum WeatherType { clear, cloudy, rain, snow, dust }

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

class ContextSnapshot {
  ContextSnapshot({
    required this.id,
    required this.observedAt,
    required this.expiresAt,
    required this.primaryScene,
    required this.dayPhase,
    required this.weather,
    required this.activeRoute,
    List<String> opportunityIds = const [],
    List<String> safetyEventIds = const [],
    List<String> wildlifeEventIds = const [],
    List<ContextEvent> events = const [],
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
    this.routeMode = ContextRouteMode.none,
    this.routeStage = ContextRouteStage.none,
    List<ContextAction> allowedActions = const [],
    this.serverManifest,
  }) : opportunityIds = List.unmodifiable(opportunityIds),
       safetyEventIds = List.unmodifiable(safetyEventIds),
       wildlifeEventIds = List.unmodifiable(wildlifeEventIds),
       events = List.unmodifiable(events),
       allowedActions = List.unmodifiable(allowedActions);

  final String id;
  final DateTime observedAt;
  final DateTime expiresAt;
  final SceneType primaryScene;
  final DayPhase dayPhase;
  final WeatherType weather;
  final bool activeRoute;
  final List<String> opportunityIds;
  final List<String> safetyEventIds;
  final List<String> wildlifeEventIds;
  final List<ContextEvent> events;
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
  final ContextRouteMode routeMode;
  final ContextRouteStage routeStage;
  final List<ContextAction> allowedActions;
  final ServerManifest? serverManifest;

  ContextSnapshot asStale() {
    final retainedEvents = events
        .where((event) => event.channel != ContextEventChannel.opportunity)
        .toList(growable: false);
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: primaryScene,
      dayPhase: dayPhase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: const [],
      safetyEventIds: safetyEventIds,
      wildlifeEventIds: wildlifeEventIds,
      events: retainedEvents,
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
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: retainedEvents
          .map((event) => event.allowedAction)
          .whereType<ContextAction>()
          .toSet()
          .toList(growable: false),
      serverManifest: serverManifest,
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
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: allowedActions,
      serverManifest: serverManifest,
    );
  }

  ContextSnapshot withRemoteContext({
    required String id,
    required DateTime expiresAt,
    required SceneType primaryScene,
    required List<ContextEvent> events,
    required DateTime remoteGeneratedAt,
    required ContextDataFreshness dataFreshness,
    required MoonPhase moonPhase,
    required double moonIllumination,
    required ContextRouteMode routeMode,
    required ContextRouteStage routeStage,
    required List<ContextAction> allowedActions,
  }) {
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: primaryScene,
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
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: allowedActions,
      serverManifest: serverManifest,
    );
  }
}
