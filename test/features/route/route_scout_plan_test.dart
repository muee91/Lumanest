import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_scout_plan.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';

void main() {
  test('critical route weather stays ahead of photography and support', () {
    final now = DateTime.utc(2026, 8, 4, 2);
    final session = ShootingSession(
      id: 'route-light',
      kind: ShootingSessionKind.routeLightWindow,
      title: '侧光窗口',
      startsAt: now.add(const Duration(minutes: 20)),
      endsAt: now.add(const Duration(minutes: 70)),
      primaryPhase: ShootingPhaseKind.shoot,
      conditionBand: ShootingConditionBand.good,
      confidenceBand: ShootingConfidenceBand.medium,
      trend: ShootingTrend.stable,
      phases: [
        ShootingSessionPhase(
          kind: ShootingPhaseKind.shoot,
          startsAt: now.add(const Duration(minutes: 25)),
          peaksAt: now.add(const Duration(minutes: 40)),
          endsAt: now.add(const Duration(minutes: 55)),
          conditionBand: ShootingConditionBand.good,
          directionDegrees: 280,
        ),
      ],
      factors: const [],
      trendSamples: const [],
      targetCandidates: const [],
      ruleVersion: 'route-light.1',
      expiresAt: now.add(const Duration(minutes: 15)),
    );
    final snapshot = ContextSnapshot(
      id: 'ctx',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.mountain,
      dayPhase: DayPhase.day,
      weather: WeatherType.cloudy,
      activeRoute: true,
      shootingSessions: [session],
    );
    final route = DrivingRoute(
      destinationName: '目的地',
      distanceMeters: 80000,
      durationSeconds: 7200,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.5, longitude: 120.5),
      ],
    );
    final weather = RouteWeatherReport(
      routeId: 'r1',
      generatedAt: now,
      source: 'QWeather',
      coverage: RouteWeatherCoverage.full,
      requestedSamples: 2,
      availableSamples: 2,
      samples: [
        RouteWeatherSample(
          progress: 0,
          expectedAt: now,
          forecastAt: now,
          condition: RouteWeatherCondition.cloudy,
          cloudCoverPercent: 70,
          windSpeedMps: 3,
          precipitationMm: 0,
          visibilityKm: 20,
          thunder: false,
          stale: false,
        ),
        RouteWeatherSample(
          progress: .5,
          expectedAt: now.add(const Duration(hours: 1)),
          forecastAt: now.add(const Duration(hours: 1)),
          condition: RouteWeatherCondition.rain,
          cloudCoverPercent: 95,
          windSpeedMps: 8,
          precipitationMm: 6,
          visibilityKm: 4,
          thunder: true,
          stale: false,
        ),
      ],
    );
    final fuel = RouteSupportStop(
      routeProgress: .45,
      place: const NearbyPlace(
        id: 'fuel-1',
        name: '沿途加油站',
        category: NearbyPlaceCategory.fuel,
        point: GeoPoint(latitude: 30.2, longitude: 120.2),
        distanceMeters: 900,
      ),
    );

    final plan = RouteScoutPlanBuilder.build(
      routeId: 'r1',
      route: route,
      snapshot: snapshot,
      now: now,
      weather: weather,
      supportStops: [fuel],
    );

    expect(plan.nodes.first.priority, RouteScoutPriority.critical);
    expect(plan.nodes.first.kind, RouteScoutNodeKind.safety);
    expect(plan.photographyCount, 1);
    expect(plan.supportCount, 1);
    expect(plan.headline, contains('天气风险'));
  });

  test('journey progress is time based and bounded', () {
    final start = DateTime.utc(2026, 8, 4, 2);
    expect(
      RouteScoutPlan.progressForJourney(
        startedAt: start,
        durationSeconds: 3600,
        now: start.add(const Duration(minutes: 30)),
      ),
      .5,
    );
    expect(
      RouteScoutPlan.progressForJourney(
        startedAt: start,
        durationSeconds: 3600,
        now: start.add(const Duration(hours: 2)),
      ),
      1,
    );
  });
}
