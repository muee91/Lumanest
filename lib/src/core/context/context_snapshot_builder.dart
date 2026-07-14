import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
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
    RouteContextState route = RouteContextState.none,
  }) {
    final scene = sceneClassifier.classify(sceneEvidence, route: route);
    final events = ruleEngine.evaluate(
      scene: scene,
      weather: weather,
      solar: solar,
      generatedAt: generatedAt,
      route: route,
    );
    final activeRoute = route.isActive && route.hasRoute;
    return ContextSnapshot(
      id: 'live-${generatedAt.microsecondsSinceEpoch}',
      observedAt: weather.observedAt,
      expiresAt: generatedAt.add(const Duration(minutes: 15)),
      primaryScene: scene,
      dayPhase: solar.dayPhase,
      weather: weather.contextWeatherType,
      activeRoute: activeRoute,
      opportunityIds: events
          .where((event) => event.channel == ContextEventChannel.opportunity)
          .map((event) => event.id)
          .toList(growable: false),
      safetyEventIds: events
          .where(
            (event) =>
                event.channel == ContextEventChannel.safety ||
                event.channel == ContextEventChannel.wildlifeSafety,
          )
          .map((event) => event.id)
          .toList(growable: false),
      wildlifeEventIds: events
          .where(
            (event) =>
                event.channel == ContextEventChannel.wildlifeOpportunity ||
                event.channel == ContextEventChannel.wildlifeSafety,
          )
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
      routeMode: route.mode,
      routeStage: route.stage,
      allowedActions: events
          .map((event) => event.allowedAction)
          .whereType<ContextAction>()
          .toSet()
          .toList(growable: false),
    );
  }
}
