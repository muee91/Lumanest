import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 10);

  test('layered cloud data enhances total cloud without inventing values', () {
    final result = EnvironmentVisualization.fromSnapshot(
      _snapshot(now, cloud: 91),
      skyWindow: _forecast(now),
      now: now,
    );

    expect(result.cloud, isNotNull);
    expect(result.cloud!.totalCloudCoverPercent, 88);
    expect(result.cloud!.lowCloudCoverPercent, 72);
    expect(result.cloud!.middleCloudCoverPercent, 46);
    expect(result.cloud!.highCloudCoverPercent, 21);
    expect(result.cloud!.hasLayeredClouds, isTrue);
    expect(result.cards.first.type, EnvironmentMetricType.cloud);
  });

  test('total-only cloud remains honest when layered data is unavailable', () {
    final result = EnvironmentVisualization.fromSnapshot(
      _snapshot(now, cloud: 64),
      now: now,
    );

    expect(result.cloud!.hasLayeredClouds, isFalse);
    expect(result.cloud!.compactLayerSummary, '总云量 64%');
    expect(result.cloud!.sourceLabel, 'Context 当前天气');
  });

  test('rain reorders actionable precipitation before cloud', () {
    final snapshot = ContextSnapshot(
      id: 'rain-order',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.rain,
      activeRoute: false,
      precipitationMillimeters: 3.2,
      cloudCoverPercent: 96,
      windSpeedMetersPerSecond: 4,
      visibilityKilometers: 9,
    );
    final result = EnvironmentVisualization.fromSnapshot(snapshot, now: now);
    expect(result.cards.first.type, EnvironmentMetricType.precipitation);
    expect(result.cards[1].type, EnvironmentMetricType.cloud);
  });

  test(
    'solar elevation is named and explained without an ambiguous light value',
    () {
      final result = EnvironmentVisualization.fromSnapshot(
        _snapshot(now, cloud: 30),
        now: now,
      );
      final light = result.cards.firstWhere(
        (card) => card.type == EnvironmentMetricType.light,
      );

      expect(light.label, '太阳高度');
      expect(light.summary, contains('地平线上方'));
    },
  );
}

ContextSnapshot _snapshot(DateTime now, {double? cloud}) => ContextSnapshot(
  id: 'visualization',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 30)),
  primaryScene: SceneType.lake,
  dayPhase: DayPhase.sunset,
  weather: WeatherType.cloudy,
  activeRoute: false,
  cloudCoverPercent: cloud,
  windSpeedMetersPerSecond: 2.2,
  visibilityKilometers: 26,
  precipitationMillimeters: 0,
  solarElevationDegrees: 8,
);

SkyWindowForecast _forecast(DateTime now) => SkyWindowForecast(
  algorithmVersion: 'sky-window-forecast.1',
  requestedCoordinate: const GeoPoint(latitude: 30, longitude: 120),
  requestedStartAt: now,
  endAt: now.add(const Duration(hours: 24)),
  stepMinutes: 15,
  generatedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  current: SkyWindowAssessment(
    observedAt: now,
    conditionBand: SkyWindowConditionBand.conditional,
    geometry: null,
    terrain: const SkyWindowTerrain(
      status: 'unavailable',
      horizonAltitudeDegrees: null,
      clearanceDegrees: null,
      obstructionDistanceKm: null,
      coverageRatio: null,
    ),
    moon: null,
    atmosphere: const SkyWindowAtmosphere(
      status: 'ready',
      conditionBand: SkyWindowConditionBand.conditional,
      totalCloudCoverPercent: 88,
      lowCloudCoverPercent: 72,
      middleCloudCoverPercent: 46,
      highCloudCoverPercent: 21,
      visibilityMeters: 26000,
      precipitationProbabilityPercent: 20,
      precipitationMm: 0,
      relativeHumidityPercent: 76,
      windSpeedKmh: 8,
      windGustKmh: 14,
    ),
    lightPollution: const SkyWindowLightPollution(
      status: 'unavailable',
      direction: null,
      p90: null,
      relativeRadianceBand: null,
      coverageRatio: null,
      dominantDirection: null,
      dominantAngularSeparationDegrees: null,
    ),
    weatherAgreement: 'strong',
    limitations: const [],
  ),
  windows: const [],
  bestWindowId: null,
  confidence: const SkyWindowConfidence(
    band: SkyWindowConfidenceBand.medium,
    criticalSourcesReady: true,
    missingSources: [],
    conflicts: [],
  ),
  calibration: const SkyBrightnessCalibration(
    status: 'unavailable',
    sampleCount: 0,
    sqmMedian: null,
    limitingMagnitudeMedian: null,
    distanceKm: null,
    limitation: null,
  ),
);
