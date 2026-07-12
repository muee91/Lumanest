import 'package:luma_nest/src/core/location/geo_point.dart';
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
       wildlifeEventIds = List.unmodifiable(wildlifeEventIds);

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
      opportunityIds: opportunityIds,
      safetyEventIds: safetyEventIds,
      wildlifeEventIds: wildlifeEventIds,
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
