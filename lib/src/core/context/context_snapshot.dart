import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
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
    this.solarElevationDegrees,
    this.solarAzimuthDegrees,
    this.sunrise,
    this.sunset,
    this.isStale = false,
  }) : opportunityIds = List.unmodifiable(opportunityIds),
       safetyEventIds = List.unmodifiable(safetyEventIds),
       wildlifeEventIds = List.unmodifiable(wildlifeEventIds),
       events = List.unmodifiable(events);

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
  final double? solarElevationDegrees;
  final double? solarAzimuthDegrees;
  final DateTime? sunrise;
  final DateTime? sunset;
  final bool isStale;

  ContextSnapshot asStale() {
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
      events: events
          .where((event) => event.channel != ContextEventChannel.opportunity)
          .toList(growable: false),
      wildlifeActivity: wildlifeActivity,
      location: location,
      temperatureCelsius: temperatureCelsius,
      windSpeedMetersPerSecond: windSpeedMetersPerSecond,
      windDirectionDegrees: windDirectionDegrees,
      visibilityKilometers: visibilityKilometers,
      precipitationMillimeters: precipitationMillimeters,
      cloudCoverPercent: cloudCoverPercent,
      solarElevationDegrees: solarElevationDegrees,
      solarAzimuthDegrees: solarAzimuthDegrees,
      sunrise: sunrise,
      sunset: sunset,
      isStale: true,
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
      solarElevationDegrees: solarElevationDegrees,
      solarAzimuthDegrees: solarAzimuthDegrees,
      sunrise: sunrise,
      sunset: sunset,
      isStale: isStale,
    );
  }
}
