import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
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
    SceneContext? sceneContext,
    bool isStale = false,
    RouteContextState route = RouteContextState.none,
  }) {
    final events = <ContextEvent>[];
    void add(
      String id,
      ContextEventChannel channel,
      ContextEventSource source,
      double confidence, {
      ContextGeoScope? geoScope,
      ContextSafetyLevel? safetyLevel,
      ContextAction? allowedAction,
      Duration evidenceTtl = const Duration(minutes: 10),
    }) {
      events.add(
        ContextEvent(
          id: id,
          channel: channel,
          source: source,
          observedAt: weather.observedAt,
          expiresAt: generatedAt.add(evidenceTtl),
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
        allowedAction: ContextAction.openSafetyDetail,
      );
    }
    if (weather.windSpeedMetersPerSecond >= 15) {
      add(
        'strong-wind',
        ContextEventChannel.safety,
        ContextEventSource.weather,
        0.9,
        allowedAction: ContextAction.openSafetyDetail,
      );
    }
    if (weather.precipitationMillimeters >= 10) {
      add(
        'heavy-rain',
        ContextEventChannel.safety,
        ContextEventSource.weather,
        0.9,
        allowedAction: ContextAction.openSafetyDetail,
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

    final primaryScene = sceneContext?.primaryScene;
    final activity = sceneContext?.activity;
    final isUrban =
        primaryScene == PrimaryScene.urban || scene == SceneType.city;
    final isWater =
        primaryScene == PrimaryScene.inlandWater ||
        primaryScene == PrimaryScene.wetland ||
        primaryScene == PrimaryScene.coast ||
        scene == SceneType.lake;
    final isMountain =
        primaryScene == PrimaryScene.mountain ||
        primaryScene == PrimaryScene.plateau ||
        scene == SceneType.mountain;
    final isDesert =
        primaryScene == PrimaryScene.desert || scene == SceneType.desert;

    if (solar.dayPhase == DayPhase.blueHour && isUrban) {
      add(
        'session.city.blue_hour',
        ContextEventChannel.opportunity,
        ContextEventSource.solar,
        0.9,
        allowedAction: ContextAction.openShootingWindow,
        evidenceTtl: const Duration(minutes: 30),
      );
    }
    if (isWater &&
        lowWind &&
        dry &&
        const {
          DayPhase.dawn,
          DayPhase.sunset,
          DayPhase.blueHour,
        }.contains(solar.dayPhase)) {
      add(
        solar.dayPhase == DayPhase.dawn
            ? 'session.water.morning'
            : 'session.water.evening',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.82,
        allowedAction: ContextAction.openShootingWindow,
        evidenceTtl: const Duration(minutes: 20),
      );
    }
    if (isMountain &&
        edgeLight &&
        clearEnough &&
        weather.visibilityKilometers >= 10) {
      add(
        solar.dayPhase == DayPhase.dawn
            ? 'session.mountain.morning'
            : 'session.mountain.evening',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.72,
        geoScope: ContextGeoScope.region,
        allowedAction: ContextAction.openShootingWindow,
        evidenceTtl: const Duration(minutes: 20),
      );
    }
    if (isDesert && weather.condition == WeatherCondition.dust && edgeLight) {
      add(
        'session.desert.side_light',
        ContextEventChannel.opportunity,
        ContextEventSource.rule,
        0.7,
        geoScope: ContextGeoScope.region,
        allowedAction: ContextAction.openShootingWindow,
        evidenceTtl: const Duration(minutes: 15),
      );
    }
    if (activity == ActivityState.hiking) {
      add(
        'trail-return-risk',
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
