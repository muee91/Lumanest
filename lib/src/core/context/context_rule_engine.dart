import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

class ContextRuleEngine {
  const ContextRuleEngine();

  List<ContextEvent> evaluate({
    required SceneType scene,
    required WeatherObservation weather,
    required SolarState solar,
    required DateTime generatedAt,
    bool isStale = false,
    RouteContextState route = RouteContextState.none,
  }) {
    final events = <ContextEvent>[];
    final expiry = generatedAt.add(const Duration(minutes: 15));

    void add(
      String id,
      ContextEventChannel channel,
      ContextEventSource source,
      double confidence, {
      ContextGeoScope? geoScope,
      ContextSafetyLevel? safetyLevel,
      ContextAction? allowedAction,
    }) {
      events.add(
        ContextEvent(
          id: id,
          channel: channel,
          source: source,
          observedAt: weather.observedAt,
          expiresAt: expiry,
          confidence: confidence,
          geoScope: geoScope,
          safetyLevel: safetyLevel,
          allowedAction: allowedAction,
        ),
      );
    }

    if (weather.hasThunder) {
      add(
        'thunderstorm',
        ContextEventChannel.safety,
        ContextEventSource.weather,
        1,
      );
    }
    if (weather.windSpeedMetersPerSecond >= 15) {
      add(
        'strong-wind',
        ContextEventChannel.safety,
        ContextEventSource.weather,
        0.9,
      );
    }
    if (weather.precipitationMillimeters >= 10) {
      add(
        'heavy-rain',
        ContextEventChannel.safety,
        ContextEventSource.weather,
        0.9,
      );
    }

    // Safety events come from authoritative weather observation only.
    // Wildlife safety risks are NOT inferred from GBIF historical records:
    // they require a structured wildlifeSafety event from a reliable source.
    // GBIF remains a wildlifeHistorical creative signal (regional-wildlife).

    if (isStale) return List.unmodifiable(events);

    final lowWind = weather.windSpeedMetersPerSecond <= 3;
    final dry = weather.precipitationMillimeters == 0;
    final clearEnough =
        weather.condition == WeatherCondition.clear ||
        weather.condition == WeatherCondition.cloudy;
    final edgeLight =
        solar.dayPhase == DayPhase.dawn || solar.dayPhase == DayPhase.sunset;

    if (solar.dayPhase == DayPhase.blueHour && scene == SceneType.city) {
      add(
        'blue-hour',
        ContextEventChannel.opportunity,
        ContextEventSource.solar,
        0.9,
      );
    }
    if (scene == SceneType.lake && lowWind && dry) {
      add(
        'reflection',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.82,
      );
    }
    if (scene == SceneType.mountain &&
        edgeLight &&
        clearEnough &&
        weather.visibilityKilometers >= 10) {
      add(
        'alpenglow',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.72,
      );
    }
    if (scene == SceneType.desert &&
        weather.condition == WeatherCondition.dust &&
        edgeLight) {
      add(
        'dust-light',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.7,
      );
    }
    if (scene == SceneType.village && edgeLight && clearEnough) {
      add(
        'humanity-light',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.65,
      );
    }
    if (scene == SceneType.driving) {
      add(
        'route-light-window',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.7,
        geoScope: ContextGeoScope.route,
        allowedAction: ContextAction.openRoute,
      );
    }
    if (scene == SceneType.hiking) {
      add(
        'hiking-return-check',
        ContextEventChannel.safety,
        ContextEventSource.rule,
        0.8,
        geoScope: ContextGeoScope.route,
        safetyLevel: ContextSafetyLevel.caution,
        allowedAction: ContextAction.openRoute,
      );
    }

    return List.unmodifiable(events);
  }
}
