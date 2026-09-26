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

  test('authoritative route closure becomes a critical safety node', () {
    final now = DateTime.utc(2026, 8, 5, 6);
    final report = _routeReport(
      now,
      restrictionStatus: RouteRestrictionStatus.present,
      kinds: const ['roadClosure'],
      authoritative: true,
      factIds: const ['notice-1'],
      evidenceStatus: RouteEvidenceStatus.verified,
      evidenceFactIds: const ['notice-1'],
    );
    final plan = RouteScoutPlanBuilder.build(
      routeId: 'r1',
      route: _route(),
      snapshot: _snapshot(now),
      now: now,
      weather: report,
    );

    final node = plan.nodes.singleWhere(
      (item) => item.id.startsWith('restriction-'),
    );
    expect(node.kind, RouteScoutNodeKind.safety);
    expect(node.priority, RouteScoutPriority.critical);
    expect(node.title, contains('官方道路关闭'));
    expect(node.detail, contains('不替代官方原文和地图导航'));
    expect(node.source, 'Road authority');
    expect(plan.headline, contains('官方管制'));
  });

  test('noneObserved restriction state never becomes a safety claim', () {
    final now = DateTime.utc(2026, 8, 5, 6);
    final report = _routeReport(
      now,
      restrictionStatus: RouteRestrictionStatus.noneObserved,
      kinds: const [],
      authoritative: false,
      factIds: const [],
      evidenceStatus: RouteEvidenceStatus.unavailable,
      evidenceFactIds: const [],
    );
    final plan = RouteScoutPlanBuilder.build(
      routeId: 'r1',
      route: _route(),
      snapshot: _snapshot(now),
      now: now,
      weather: report,
    );

    expect(
      plan.nodes.where((item) => item.id.startsWith('restriction-')),
      isEmpty,
    );
    expect(
      plan.nodes.where((item) => item.kind == RouteScoutNodeKind.safety),
      isEmpty,
    );
  });
}

DrivingRoute _route() => DrivingRoute(
  destinationName: '目的地',
  distanceMeters: 50000,
  durationSeconds: 3600,
  tollsYuan: 0.0,
  polyline: [
    GeoPoint(latitude: 30, longitude: 120),
    GeoPoint(latitude: 30.5, longitude: 120.5),
  ],
);

ContextSnapshot _snapshot(DateTime now) => ContextSnapshot(
  id: 'ctx-route-restriction',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  primaryScene: SceneType.city,
  dayPhase: DayPhase.day,
  weather: WeatherType.clear,
  activeRoute: true,
);

RouteWeatherReport _routeReport(
  DateTime now, {
  required RouteRestrictionStatus restrictionStatus,
  required List<String> kinds,
  required bool authoritative,
  required List<String> factIds,
  required RouteEvidenceStatus evidenceStatus,
  required List<String> evidenceFactIds,
}) => RouteWeatherReport(
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
      condition: RouteWeatherCondition.clear,
      cloudCoverPercent: 10,
      windSpeedMps: 2,
      precipitationMm: 0,
      visibilityKm: 30,
      thunder: false,
      stale: false,
    ),
    RouteWeatherSample(
      progress: 1,
      expectedAt: now.add(const Duration(hours: 1)),
      forecastAt: now.add(const Duration(hours: 1)),
      condition: RouteWeatherCondition.clear,
      cloudCoverPercent: 10,
      windSpeedMps: 2,
      precipitationMm: 0,
      visibilityKm: 30,
      thunder: false,
      stale: false,
    ),
  ],
  corridor: RouteCorridorIntelligence(
    contractVersion: 1,
    generatedAt: now,
    coverage: RouteCorridorCoverage.full,
    requestedSegments: 2,
    availableSegments: 2,
    sources: const [
      RouteCorridorSource(
        id: 'official-notices',
        title: 'Official notices',
        publisher: 'Road authority',
        url: 'https://example.gov/notices',
      ),
    ],
    segments: [
      RouteCorridorSegment(
        progress: .5,
        expectedAt: now.add(const Duration(minutes: 30)),
        facilities: const RouteCorridorFacilities(
          status: RouteCorridorReferenceStatus.empty,
          parking: 0,
          fuel: 0,
          food: 0,
          water: 0,
          toilets: 0,
          shelter: 0,
          restArea: 0,
        ),
        photography: const RouteCorridorPhotography(
          status: RouteCorridorReferenceStatus.noReference,
          viewpointCount: 0,
          heritageCount: 0,
        ),
        restrictions: RouteCorridorRestrictions(
          status: restrictionStatus,
          kinds: kinds,
          authoritative: authoritative,
          factIds: factIds,
        ),
        evidence: RouteCorridorEvidence(
          status: evidenceStatus,
          factIds: evidenceFactIds,
        ),
      ),
      RouteCorridorSegment(
        progress: 1,
        expectedAt: now.add(const Duration(hours: 1)),
        facilities: const RouteCorridorFacilities(
          status: RouteCorridorReferenceStatus.unavailable,
          parking: 0,
          fuel: 0,
          food: 0,
          water: 0,
          toilets: 0,
          shelter: 0,
          restArea: 0,
        ),
        photography: const RouteCorridorPhotography(
          status: RouteCorridorReferenceStatus.unavailable,
          viewpointCount: 0,
          heritageCount: 0,
        ),
        restrictions: RouteCorridorRestrictions(
          status: RouteRestrictionStatus.unavailable,
          kinds: const [],
          authoritative: false,
          factIds: const [],
        ),
        evidence: RouteCorridorEvidence(
          status: RouteEvidenceStatus.unavailable,
          factIds: const [],
        ),
      ),
    ],
    limitations: const [
      'absence_of_official_notice_is_not_safety_confirmation',
    ],
  ),
);
