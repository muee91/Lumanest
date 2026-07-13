import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/core/context/context_rule_engine.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';

class ContextSnapshotBuilder {
  const ContextSnapshotBuilder({
    this.sceneClassifier = const SceneClassifier(),
    this.ruleEngine = const ContextRuleEngine(),
  });

  final SceneClassifier sceneClassifier;
  final ContextRuleEngine ruleEngine;

  ContextSnapshot build({
    required LocationReading location,
    required WeatherObservation weather,
    required SolarState solar,
    required DateTime generatedAt,
    SceneEvidence sceneEvidence = const SceneEvidence(),
  }) {
    final scene = sceneClassifier.classify(sceneEvidence);
    final events = ruleEngine.evaluate(
      scene: scene,
      weather: weather,
      solar: solar,
      generatedAt: generatedAt,
    );
    return ContextSnapshot(
      id: 'live-${generatedAt.microsecondsSinceEpoch}',
      observedAt: weather.observedAt,
      expiresAt: generatedAt.add(const Duration(minutes: 15)),
      primaryScene: scene,
      dayPhase: solar.dayPhase,
      weather: weather.contextWeatherType,
      activeRoute: false,
      opportunityIds: events
          .where((event) => event.channel == ContextEventChannel.opportunity)
          .map((event) => event.id)
          .toList(growable: false),
      safetyEventIds: events
          .where((event) => event.channel == ContextEventChannel.safety)
          .map((event) => event.id)
          .toList(growable: false),
      events: events,
      location: location.point,
      temperatureCelsius: weather.temperatureCelsius,
      windSpeedMetersPerSecond: weather.windSpeedMetersPerSecond,
      windDirectionDegrees: weather.windDirectionDegrees,
      visibilityKilometers: weather.visibilityKilometers,
      precipitationMillimeters: weather.precipitationMillimeters,
      cloudCoverPercent: weather.cloudCoverPercent,
      solarElevationDegrees: solar.elevationDegrees,
      solarAzimuthDegrees: solar.azimuthDegrees,
      sunrise: solar.sunrise,
      sunset: solar.sunset,
    );
  }
}
