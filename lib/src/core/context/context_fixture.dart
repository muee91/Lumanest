import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

abstract final class ContextFixtures {
  static final _baseTime = DateTime.utc(2026, 7, 11, 10);

  static ContextSnapshot quietCity() {
    return ContextSnapshot(
      id: 'fixture-city-quiet',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 30)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
    );
  }

  static ContextSnapshot lakeSunset({DateTime? observedAt}) {
    final eventTime = observedAt?.toUtc() ?? _baseTime;
    return ContextSnapshot(
      id: 'fixture-lake-sunset',
      observedAt: eventTime,
      expiresAt: eventTime.add(const Duration(minutes: 20)),
      primaryScene: SceneType.lake,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      activeRoute: false,
      location: const GeoPoint(latitude: 30.25, longitude: 120.15),
      windSpeedMetersPerSecond: 2.1,
      visibilityKilometers: 26,
      precipitationMillimeters: 0,
      cloudCoverPercent: 58,
      opportunityIds: const ['session.water.evening'],
      events: [
        ContextEvent(
          id: 'session.water.evening',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.rule,
          observedAt: eventTime,
          expiresAt: eventTime.add(const Duration(minutes: 20)),
          confidence: 0.82,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openShootingWindow,
        ),
      ],
      allowedActions: const [ContextAction.openShootingWindow],
      shootingSessions: [waterEveningSession(observedAt: eventTime)],
    );
  }

  static ShootingSession waterEveningSession({
    required DateTime observedAt,
    List<ShootingTarget> targetCandidates = const [],
    ShootingConditionBand conditionBand = ShootingConditionBand.good,
    ShootingConfidenceBand confidenceBand = ShootingConfidenceBand.high,
    ShootingTrend trend = ShootingTrend.improving,
  }) {
    final at = observedAt.toUtc();
    final sunsetStart = at.add(const Duration(minutes: 10));
    final reflectionStart = at.add(const Duration(minutes: 25));
    final blueStart = at.add(const Duration(minutes: 35));
    return ShootingSession(
      id: 'session_0123456789abcdef01234567',
      kind: ShootingSessionKind.waterEvening,
      title: '湖岸晚间窗口',
      startsAt: sunsetStart,
      endsAt: at.add(const Duration(minutes: 75)),
      primaryPhase: ShootingPhaseKind.reflection,
      conditionBand: conditionBand,
      confidenceBand: confidenceBand,
      trend: trend,
      phases: [
        ShootingSessionPhase(
          kind: ShootingPhaseKind.sunset,
          startsAt: sunsetStart,
          peaksAt: at.add(const Duration(minutes: 20)),
          endsAt: at.add(const Duration(minutes: 35)),
          conditionBand: ShootingConditionBand.fair,
          directionDegrees: 286,
        ),
        ShootingSessionPhase(
          kind: ShootingPhaseKind.reflection,
          startsAt: reflectionStart,
          peaksAt: at.add(const Duration(minutes: 40)),
          endsAt: at.add(const Duration(minutes: 55)),
          conditionBand: conditionBand,
          directionDegrees: 282,
        ),
        ShootingSessionPhase(
          kind: ShootingPhaseKind.blueHour,
          startsAt: blueStart,
          peaksAt: at.add(const Duration(minutes: 55)),
          endsAt: at.add(const Duration(minutes: 75)),
          conditionBand: ShootingConditionBand.good,
          directionDegrees: 278,
        ),
      ],
      factors: [
        ShootingSessionFactor(
          id: 'cloud',
          effect: ShootingFactorEffect.supporting,
          label: '云量',
          value: '58%',
          sourceAt: at,
        ),
        ShootingSessionFactor(
          id: 'wind',
          effect: ShootingFactorEffect.supporting,
          label: '风速',
          value: '2.1m/s',
          sourceAt: at,
        ),
        ShootingSessionFactor(
          id: 'precipitation',
          effect: ShootingFactorEffect.supporting,
          label: '降水',
          value: '0.0mm',
          sourceAt: at,
        ),
        ShootingSessionFactor(
          id: 'visibility',
          effect: ShootingFactorEffect.supporting,
          label: '能见度',
          value: '26km',
          sourceAt: at,
        ),
      ],
      trendSamples: [
        ShootingSessionTrendSample(
          at: at,
          conditionIndex: 58,
          cloudCoverPercent: 72,
          windSpeedMps: 3.8,
          precipitationMm: 0,
        ),
        ShootingSessionTrendSample(
          at: at.add(const Duration(minutes: 25)),
          conditionIndex: 72,
          cloudCoverPercent: 60,
          windSpeedMps: 2.4,
          precipitationMm: 0,
        ),
        ShootingSessionTrendSample(
          at: at.add(const Duration(minutes: 55)),
          conditionIndex: 82,
          cloudCoverPercent: 48,
          windSpeedMps: 1.8,
          precipitationMm: 0,
        ),
      ],
      targetCandidates: targetCandidates,
      recommendedCapabilities: const [EquipmentCapability.tripod],
      ruleVersion: 'water-evening.1',
      expiresAt: at.add(const Duration(minutes: 15)),
    );
  }

  static ShootingSession waterMorningSession({
    required DateTime observedAt,
    Duration startsAfter = const Duration(minutes: 10),
    ShootingConditionBand conditionBand = ShootingConditionBand.good,
    ShootingConfidenceBand confidenceBand = ShootingConfidenceBand.high,
  }) {
    final at = observedAt.toUtc();
    final blueStart = at.add(startsAfter);
    final sunriseStart = blueStart.add(const Duration(minutes: 35));
    return ShootingSession(
      id: 'session_89abcdef0123456789abcdef',
      kind: ShootingSessionKind.waterMorning,
      title: '湖岸晨光窗口',
      startsAt: blueStart,
      endsAt: sunriseStart.add(const Duration(minutes: 55)),
      primaryPhase: ShootingPhaseKind.sunrise,
      conditionBand: conditionBand,
      confidenceBand: confidenceBand,
      trend: ShootingTrend.improving,
      phases: [
        ShootingSessionPhase(
          kind: ShootingPhaseKind.morningBlueHour,
          startsAt: blueStart,
          peaksAt: blueStart.add(const Duration(minutes: 15)),
          endsAt: sunriseStart,
          conditionBand: ShootingConditionBand.fair,
          directionDegrees: 72,
        ),
        ShootingSessionPhase(
          kind: ShootingPhaseKind.sunrise,
          startsAt: sunriseStart,
          peaksAt: sunriseStart.add(const Duration(minutes: 15)),
          endsAt: sunriseStart.add(const Duration(minutes: 55)),
          conditionBand: conditionBand,
          directionDegrees: 76,
        ),
      ],
      factors: [
        ShootingSessionFactor(
          id: 'cloud',
          effect: ShootingFactorEffect.supporting,
          label: '云量',
          value: '55%',
          sourceAt: at,
        ),
        ShootingSessionFactor(
          id: 'wind',
          effect: ShootingFactorEffect.supporting,
          label: '风速',
          value: '1.8m/s',
          sourceAt: at,
        ),
      ],
      trendSamples: [
        ShootingSessionTrendSample(
          at: blueStart,
          conditionIndex: 60,
          cloudCoverPercent: 65,
          windSpeedMps: 2.5,
          precipitationMm: 0,
        ),
        ShootingSessionTrendSample(
          at: sunriseStart,
          conditionIndex: 78,
          cloudCoverPercent: 55,
          windSpeedMps: 1.8,
          precipitationMm: 0,
        ),
      ],
      targetCandidates: const [],
      recommendedCapabilities: const [EquipmentCapability.tripod],
      ruleVersion: 'water-morning.1',
      expiresAt: at.add(const Duration(minutes: 15)),
    );
  }

  static ContextSnapshot mountainDawn() {
    return ContextSnapshot(
      id: 'fixture-mountain-dawn',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 15)),
      primaryScene: SceneType.mountain,
      dayPhase: DayPhase.dawn,
      weather: WeatherType.clear,
      activeRoute: false,
      opportunityIds: const ['session.mountain.morning'],
      events: [
        ContextEvent(
          id: 'session.mountain.morning',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: _baseTime,
          expiresAt: _baseTime.add(const Duration(minutes: 15)),
          confidence: 0.76,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openShootingWindow,
        ),
      ],
      allowedActions: const [ContextAction.openShootingWindow],
    );
  }

  /// Desert dusk fixture with the active Core side-light session.
  static ContextSnapshot desertDusk() {
    final observedAt = DateTime.utc(2026, 7, 11, 18);
    return ContextSnapshot(
      id: 'fixture-desert-dusk',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 25)),
      primaryScene: SceneType.desert,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: false,
      location: const GeoPoint(latitude: 38.9, longitude: 92.3),
      temperatureCelsius: 34.5,
      windSpeedMetersPerSecond: 2.1,
      visibilityKilometers: 30,
      cloudCoverPercent: 5,
      solarElevationDegrees: 8.2,
      opportunityIds: const ['session.desert.side_light'],
      events: [
        ContextEvent(
          id: 'session.desert.side_light',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.weather,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 25)),
          confidence: 0.72,
          geoScope: ContextGeoScope.point,
          allowedAction: ContextAction.openShootingWindow,
        ),
      ],
      allowedActions: const [ContextAction.openShootingWindow],
    );
  }

  /// Village morning fixture without a factual Core opportunity.
  static ContextSnapshot villageMorning() {
    final observedAt = DateTime.utc(2026, 7, 11, 5, 45);
    return ContextSnapshot(
      id: 'fixture-village-morning',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 20)),
      primaryScene: SceneType.village,
      dayPhase: DayPhase.dawn,
      weather: WeatherType.clear,
      activeRoute: false,
      location: const GeoPoint(latitude: 27.7, longitude: 99.8),
      temperatureCelsius: 12.0,
      windSpeedMetersPerSecond: 1.5,
      visibilityKilometers: 15,
      cloudCoverPercent: 12,
      solarElevationDegrees: -2.5,
      opportunityIds: const [],
      events: const [],
      allowedActions: const [],
    );
  }

  /// Driving active-route fixture with the current route session.
  static ContextSnapshot drivingActiveRoute() {
    final observedAt = DateTime.utc(2026, 7, 11, 16, 30);
    return ContextSnapshot(
      id: 'fixture-driving-active',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 15)),
      primaryScene: SceneType.unknown,
      sceneContext: SceneContext(
        primaryScene: PrimaryScene.unknown,
        facets: const {SceneFacet.openRoad},
        activity: ActivityState.driving,
      ),
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: true,
      location: const GeoPoint(latitude: 30.6, longitude: 104.1),
      temperatureCelsius: 28.3,
      windSpeedMetersPerSecond: 3.0,
      visibilityKilometers: 25,
      cloudCoverPercent: 20,
      solarElevationDegrees: 35.0,
      routeMode: ContextRouteMode.driving,
      routeStage: ContextRouteStage.active,
      opportunityIds: const ['session.route.light_window'],
      events: [
        ContextEvent(
          id: 'session.route.light_window',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 15)),
          confidence: 0.58,
          geoScope: ContextGeoScope.route,
          allowedAction: ContextAction.openRoute,
        ),
      ],
      allowedActions: const [ContextAction.openRoute],
    );
  }

  /// Hiking trail fixture — active hiking context with a
  /// hiking-return-check safety event.
  static ContextSnapshot hikingTrail() {
    final observedAt = DateTime.utc(2026, 7, 11, 14, 0);
    return ContextSnapshot(
      id: 'fixture-hiking-trail',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(minutes: 30)),
      primaryScene: SceneType.mountain,
      sceneContext: SceneContext(
        primaryScene: PrimaryScene.mountain,
        facets: const {SceneFacet.reviewedViewpoint},
        activity: ActivityState.hiking,
      ),
      dayPhase: DayPhase.day,
      weather: WeatherType.cloudy,
      activeRoute: true,
      location: const GeoPoint(latitude: 31.2, longitude: 103.5),
      temperatureCelsius: 15.6,
      windSpeedMetersPerSecond: 4.2,
      visibilityKilometers: 8,
      cloudCoverPercent: 70,
      solarElevationDegrees: 22.0,
      routeMode: ContextRouteMode.hiking,
      routeStage: ContextRouteStage.active,
      safetyEventIds: const ['hiking-return-check'],
      events: [
        ContextEvent(
          id: 'hiking-return-check',
          channel: ContextEventChannel.safety,
          source: ContextEventSource.rule,
          observedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 30)),
          confidence: 0.8,
          geoScope: ContextGeoScope.route,
          safetyLevel: ContextSafetyLevel.caution,
          allowedAction: ContextAction.openSafetyDetail,
        ),
      ],
      allowedActions: const [ContextAction.openSafetyDetail],
    );
  }
}
