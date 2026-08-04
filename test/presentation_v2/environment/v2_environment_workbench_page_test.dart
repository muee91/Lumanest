import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_workbench_page.dart';

void main() {
  testWidgets('workbench survives compact width and enlarged text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final snapshot = _snapshot();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 900),
              textScaler: TextScaler.linear(1.3),
            ),
            child: V2EnvironmentWorkbenchPage(
              initialSnapshot: snapshot,
              initialForecast: _forecast(snapshot),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('摄影环境工作台'), findsOneWidget);
    expect(find.byKey(const Key('v2-environment-summary')), findsOneWidget);
    expect(find.byKey(const Key('v2-workbench-fact-cloud')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('v2-window-sample-chart')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('v2-window-sample-chart')), findsOneWidget);

    await tester.tap(find.text('阵风'));
    await tester.pumpAndSettle();
    expect(find.text('km/h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial stale data does not invent missing cards or charts', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 4, 10);
    final snapshot = ContextSnapshot(
      id: 'partial',
      observedAt: now,
      expiresAt: now.subtract(const Duration(minutes: 1)),
      primaryScene: SceneType.village,
      dayPhase: DayPhase.blueHour,
      weather: WeatherType.unknown,
      activeRoute: false,
      temperatureCelsius: 18,
      isStale: true,
      dataFreshness: ContextDataFreshness.stale,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V2EnvironmentWorkbenchPage(initialSnapshot: snapshot),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近有效事实、候选窗口峰值与摄影影响'), findsOneWidget);
    expect(find.byKey(const Key('v2-workbench-fact-temperature')), findsOneWidget);
    expect(find.byKey(const Key('v2-workbench-fact-cloud')), findsNothing);

    final emptyTrend = find.text('候选窗口采样不足，暂不绘制变化图');
    await tester.scrollUntilVisible(
      emptyTrend,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(emptyTrend, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ContextSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 4, 10);
  return ContextSnapshot(
    id: 'workbench-test',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 15)),
    primaryScene: SceneType.mountain,
    dayPhase: DayPhase.sunset,
    weather: WeatherType.cloudy,
    activeRoute: false,
    location: const GeoPoint(latitude: 30.27, longitude: 120.15),
    temperatureCelsius: 23,
    windSpeedMetersPerSecond: 4.5,
    windDirectionDegrees: 220,
    visibilityKilometers: 18,
    precipitationMillimeters: 0,
    cloudCoverPercent: 58,
    airQualityIndex: 42,
    airQualityCategory: '优',
    airQualityObservedAt: now,
    airQualityStale: false,
    solarElevationDegrees: 4.2,
    sunrise: now.subtract(const Duration(hours: 4)),
    sunset: now.add(const Duration(hours: 1)),
  );
}

SkyWindowForecast _forecast(ContextSnapshot snapshot) {
  final now = snapshot.observedAt;
  final assessments = <SkyWindowAssessment>[
    _assessment(now, cloud: 58, visibilityKm: 18, gustKmh: 22),
    _assessment(
      now.add(const Duration(hours: 2)),
      cloud: 42,
      visibilityKm: 24,
      gustKmh: 18,
    ),
    _assessment(
      now.add(const Duration(hours: 4)),
      cloud: 68,
      visibilityKm: 16,
      gustKmh: 31,
    ),
  ];
  final windows = [
    for (var index = 1; index < assessments.length; index += 1)
      SkyWindowCandidate(
        id: 'window-$index',
        startAt: assessments[index].observedAt.subtract(
          const Duration(minutes: 30),
        ),
        endAt: assessments[index].observedAt.add(
          const Duration(minutes: 30),
        ),
        peakAt: assessments[index].observedAt,
        conditionBand: index == 1
            ? SkyWindowConditionBand.favorable
            : SkyWindowConditionBand.conditional,
        sampleCount: 4,
        favorableSamples: index == 1 ? 4 : 0,
        conditionalSamples: index == 1 ? 0 : 4,
        peakAssessment: assessments[index],
        primaryReasons: const [],
      ),
  ];
  return SkyWindowForecast(
    algorithmVersion: 'sky-window-forecast.1',
    requestedCoordinate: snapshot.location!,
    requestedStartAt: now,
    endAt: now.add(const Duration(hours: 6)),
    stepMinutes: 15,
    generatedAt: now,
    expiresAt: now.add(const Duration(minutes: 15)),
    current: assessments.first,
    windows: windows,
    bestWindowId: windows.first.id,
    confidence: const SkyWindowConfidence(
      band: SkyWindowConfidenceBand.medium,
      criticalSourcesReady: true,
      missingSources: ['seven_timer_auxiliary'],
      conflicts: [],
    ),
    calibration: const SkyBrightnessCalibration(
      status: 'unconfigured',
      sampleCount: 0,
      sqmMedian: null,
      limitingMagnitudeMedian: null,
      distanceKm: null,
      limitation: null,
    ),
  );
}

SkyWindowAssessment _assessment(
  DateTime at, {
  required double cloud,
  required double visibilityKm,
  required double gustKmh,
}) => SkyWindowAssessment(
  observedAt: at,
  conditionBand: SkyWindowConditionBand.conditional,
  geometry: null,
  terrain: const SkyWindowTerrain(
    status: 'ready',
    horizonAltitudeDegrees: 2,
    clearanceDegrees: 8,
    obstructionDistanceKm: 5,
    coverageRatio: .9,
  ),
  moon: null,
  atmosphere: SkyWindowAtmosphere(
    status: 'ready',
    conditionBand: SkyWindowConditionBand.conditional,
    totalCloudCoverPercent: cloud,
    lowCloudCoverPercent: cloud * .35,
    middleCloudCoverPercent: cloud * .55,
    highCloudCoverPercent: cloud * .8,
    visibilityMeters: visibilityKm * 1000,
    precipitationProbabilityPercent: 15,
    precipitationMm: 0,
    relativeHumidityPercent: 65,
    windSpeedKmh: 14,
    windGustKmh: gustKmh,
  ),
  lightPollution: const SkyWindowLightPollution(
    status: 'ready',
    direction: 'west',
    p90: .2,
    relativeRadianceBand: 'dark',
    coverageRatio: .9,
    dominantDirection: 'east',
    dominantAngularSeparationDegrees: 90,
  ),
  weatherAgreement: 'aligned',
  limitations: const [],
);
