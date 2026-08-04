import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/environment/sky_window_timeline.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_timeline_page.dart';

void main() {
  testWidgets('timeline survives compact width and switches metrics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = _snapshot();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(1.3),
            ),
            child: V2EnvironmentTimelinePage(
              initialSnapshot: snapshot,
              initialTimeline: _timeline(snapshot),
              initialFocus: EnvironmentTimelineFocus.cloud,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('摄影环境工作台'), findsOneWidget);
    expect(find.byKey(const Key('v2-timeline-summary')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('v2-timeline-chart-cloud')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('v2-timeline-chart-cloud')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final windFocus = find.byKey(const Key('v2-timeline-focus-wind'));
    await tester.ensureVisible(windFocus);
    await tester.pumpAndSettle();
    await tester.tap(windFocus);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('v2-timeline-chart-wind')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing timeline stays honest and keeps current facts', (
    tester,
  ) async {
    final snapshot = _snapshot();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V2EnvironmentTimelinePage(initialSnapshot: snapshot),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前事实可用；连续预报增强暂不可用'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('v2-timeline-empty')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('v2-timeline-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ContextSnapshot _snapshot() {
  final now = DateTime.utc(2026, 8, 4, 10);
  return ContextSnapshot(
    id: 'timeline-test',
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
    solarElevationDegrees: 4.2,
    sunrise: now.subtract(const Duration(hours: 4)),
    sunset: now.add(const Duration(hours: 1)),
  );
}

SkyWindowTimelineForecast _timeline(ContextSnapshot snapshot) {
  final start = snapshot.observedAt;
  final end = start.add(const Duration(hours: 6));
  final assessment = _assessment(start);
  final forecast = SkyWindowForecast(
    algorithmVersion: 'sky-window-forecast.1',
    requestedCoordinate: snapshot.location!,
    requestedStartAt: start,
    endAt: end,
    stepMinutes: 15,
    generatedAt: start,
    expiresAt: start.add(const Duration(minutes: 15)),
    current: assessment,
    windows: const [],
    bestWindowId: null,
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
  return SkyWindowTimelineForecast(
    forecast: forecast,
    samples: [
      for (var index = 0; index <= 24; index += 1)
        SkyWindowTimelineSample(
          validAt: start.add(Duration(minutes: 15 * index)),
          conditionBand: index.isEven
              ? SkyWindowConditionBand.conditional
              : SkyWindowConditionBand.favorable,
          sunAltitudeDegrees: 4 - index.toDouble(),
          astronomicalNight: index > 12,
          totalCloudCoverPercent: 58 - index / 2,
          lowCloudCoverPercent: 25 + index / 3,
          middleCloudCoverPercent: 34 + index / 4,
          highCloudCoverPercent: 62 - index / 5,
          visibilityMeters: 18000 + index * 300,
          precipitationProbabilityPercent: index.toDouble(),
          precipitationMm: 0,
          relativeHumidityPercent: 65,
          windSpeedKmh: 14 + index / 5,
          windGustKmh: 22 + index / 3,
          weatherAgreement: 'aligned',
          limitations: const [],
        ),
    ],
  );
}

SkyWindowAssessment _assessment(DateTime at) => SkyWindowAssessment(
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
      atmosphere: const SkyWindowAtmosphere(
        status: 'ready',
        conditionBand: SkyWindowConditionBand.conditional,
        totalCloudCoverPercent: 58,
        lowCloudCoverPercent: 25,
        middleCloudCoverPercent: 34,
        highCloudCoverPercent: 62,
        visibilityMeters: 18000,
        precipitationProbabilityPercent: 10,
        precipitationMm: 0,
        relativeHumidityPercent: 65,
        windSpeedKmh: 14,
        windGustKmh: 22,
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
