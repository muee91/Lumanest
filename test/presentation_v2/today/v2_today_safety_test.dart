import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart' as context;
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';

void main() {
  testWidgets('Today date follows the refreshed snapshot generation time', (
    tester,
  ) async {
    final generatedAt = DateTime(2030, 1, 3, 0, 5).toUtc();
    final snapshot = ContextSnapshot(
      id: 'ctx_today_date',
      observedAt: generatedAt.subtract(const Duration(minutes: 10)),
      expiresAt: generatedAt.add(const Duration(minutes: 10)),
      remoteGeneratedAt: generatedAt,
      primaryScene: SceneType.city,
      dayPhase: DayPhase.night,
      weather: WeatherType.clear,
      activeRoute: false,
    );

    await tester.pumpWidget(_host(snapshot));

    expect(find.text('1月3日 · 夜间'), findsOneWidget);
  });

  final now = DateTime.now().toUtc();

  testWidgets('warning stays in the top-right while photography remains hero', (
    tester,
  ) async {
    final snapshot = _snapshotWithSafety(now);
    await tester.pumpWidget(_host(snapshot));
    await tester.pump();

    expect(find.byKey(const Key('v2-safety-alert-button')), findsOneWidget);
    expect(find.byKey(const Key('v2-safety-object')), findsNothing);
    expect(find.text('这个窗口值得你提前到场。'), findsOneWidget);
    expect(find.byKey(const Key('v2-today-judgement')), findsOneWidget);
    expect(find.text('先把风险放在所有创作之前。'), findsNothing);
  });

  testWidgets('warning button opens the safety detail sheet', (tester) async {
    await tester.pumpWidget(_host(_snapshotWithSafety(now)));
    await tester.pump();

    expect(find.text('雷暴正在接近'), findsNothing);
    await tester.tap(find.byKey(const Key('v2-safety-alert-button')));
    await tester.pumpAndSettle();

    expect(find.text('雷暴正在接近'), findsOneWidget);
    expect(find.textContaining('请远离制高点'), findsOneWidget);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.showDragHandle, isFalse);
    expect(sheet.enableDrag, isFalse);
  });

  testWidgets('no warning renders no button and reserves no space', (
    tester,
  ) async {
    await tester.pumpWidget(_host(ContextFixtures.lakeSunset(observedAt: now)));
    await tester.pump();

    expect(find.byKey(const Key('v2-safety-alert-button')), findsNothing);
    expect(find.text('预警'), findsNothing);
    expect(find.text('这个窗口值得你提前到场。'), findsOneWidget);
  });

  testWidgets('reliable current conditions enrich the hero without shortcuts', (
    tester,
  ) async {
    await tester.pumpWidget(_host(ContextFixtures.lakeSunset(observedAt: now)));
    await tester.pump();

    expect(find.byKey(const Key('v2-current-conditions')), findsOneWidget);
    expect(find.text('此刻条件'), findsOneWidget);
    expect(find.text('多云'), findsOneWidget);
    expect(find.text('2.1 m/s'), findsOneWidget);
    expect(find.text('26 km'), findsOneWidget);
    expect(find.text('0.0 mm'), findsOneWidget);
    expect(find.text('换个方向看看'), findsNothing);
    expect(find.text('抽一张灵感'), findsNothing);
  });

  testWidgets('current conditions reserve no space without reliable facts', (
    tester,
  ) async {
    final snapshot = ContextSnapshot(
      id: 'empty-conditions',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      primaryScene: SceneType.unknown,
      dayPhase: DayPhase.day,
      weather: WeatherType.unknown,
      activeRoute: false,
    );

    await tester.pumpWidget(_host(snapshot));
    await tester.pump();

    expect(find.byKey(const Key('v2-current-conditions')), findsNothing);
    expect(find.text('此刻条件'), findsNothing);
    expect(find.text('最近条件'), findsNothing);
  });

  testWidgets('stale facts are honestly labelled as recent conditions', (
    tester,
  ) async {
    final base = ContextFixtures.lakeSunset(observedAt: now);

    await tester.pumpWidget(_host(_withFreshness(base, stale: true)));
    await tester.pump();

    expect(find.byKey(const Key('v2-current-conditions')), findsOneWidget);
    expect(find.text('最近条件'), findsOneWidget);
    expect(find.text('此刻条件'), findsNothing);
  });

  testWidgets('far-future sessions stay off Today instead of reserving rail', (
    tester,
  ) async {
    final base = ContextFixtures.lakeSunset(observedAt: now);
    final tomorrowMorning = ContextFixtures.waterMorningSession(
      observedAt: now,
      startsAfter: const Duration(hours: 10),
    );

    await tester.pumpWidget(
      _host(_withSessions(base, [...base.shootingSessions, tomorrowMorning])),
    );
    await tester.pump();

    expect(find.text('湖岸晨光窗口'), findsNothing);
    expect(
      find.byKey(const Key('v2-secondary-opportunity-rail')),
      findsNothing,
    );
  });

  testWidgets('nearby secondary session uses local time without truncation', (
    tester,
  ) async {
    final base = ContextFixtures.lakeSunset(observedAt: now);
    final nearbyMorning = ContextFixtures.waterMorningSession(
      observedAt: now,
      startsAfter: const Duration(hours: 2),
    );
    final snapshot = _withSessions(base, [
      ...base.shootingSessions,
      nearbyMorning,
    ]);

    await tester.pumpWidget(_host(snapshot));
    await tester.pump();

    final timeFinder = find.byKey(
      Key('v2-secondary-session-time-${nearbyMorning.id}'),
    );
    expect(timeFinder, findsOneWidget);
    final label = tester.widget<Text>(timeFinder);
    final start = nearbyMorning.startsAt.toLocal();
    final end = nearbyMorning.endsAt.toLocal();
    String f(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    expect(label.data, contains('${f(start)}—${f(end)}'));
    expect(label.data, endsWith('· 条件较好'));
    expect(label.overflow, isNull);
    expect(
      find.ancestor(of: timeFinder, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
  });
}

Widget _host(ContextSnapshot snapshot) => ProviderScope(
  overrides: [currentTimeProvider.overrideWithValue(() => snapshot.observedAt)],
  child: MaterialApp(home: V2TodayPage(initialSnapshot: snapshot)),
);

ContextSnapshot _withSessions(
  ContextSnapshot base,
  List<ShootingSession> shootingSessions,
) => ContextSnapshot(
  id: base.id,
  observedAt: base.observedAt,
  expiresAt: base.expiresAt,
  primaryScene: base.primaryScene,
  sceneContext: base.sceneContext,
  dayPhase: base.dayPhase,
  weather: base.weather,
  activeRoute: base.activeRoute,
  opportunityIds: base.opportunityIds,
  safetyEventIds: base.safetyEventIds,
  wildlifeEventIds: base.wildlifeEventIds,
  events: base.events,
  shootingSessions: shootingSessions,
  wildlifeActivity: base.wildlifeActivity,
  location: base.location,
  temperatureCelsius: base.temperatureCelsius,
  windSpeedMetersPerSecond: base.windSpeedMetersPerSecond,
  windDirectionDegrees: base.windDirectionDegrees,
  visibilityKilometers: base.visibilityKilometers,
  precipitationMillimeters: base.precipitationMillimeters,
  cloudCoverPercent: base.cloudCoverPercent,
  airQualityIndex: base.airQualityIndex,
  airQualityCategory: base.airQualityCategory,
  primaryPollutant: base.primaryPollutant,
  airQualityObservedAt: base.airQualityObservedAt,
  airQualityStale: base.airQualityStale,
  solarElevationDegrees: base.solarElevationDegrees,
  solarAzimuthDegrees: base.solarAzimuthDegrees,
  sunrise: base.sunrise,
  sunset: base.sunset,
  isStale: base.isStale,
  remoteGeneratedAt: base.remoteGeneratedAt,
  dataFreshness: base.dataFreshness,
  moonPhase: base.moonPhase,
  moonIllumination: base.moonIllumination,
  routeMode: base.routeMode,
  routeStage: base.routeStage,
  allowedActions: base.allowedActions,
  serverManifest: base.serverManifest,
  entries: base.entries,
  canonicalEntriesPresent: base.canonicalEntriesPresent,
);

ContextSnapshot _withFreshness(ContextSnapshot base, {required bool stale}) =>
    ContextSnapshot(
      id: base.id,
      observedAt: base.observedAt,
      expiresAt: base.expiresAt,
      primaryScene: base.primaryScene,
      sceneContext: base.sceneContext,
      dayPhase: base.dayPhase,
      weather: base.weather,
      activeRoute: base.activeRoute,
      opportunityIds: base.opportunityIds,
      safetyEventIds: base.safetyEventIds,
      wildlifeEventIds: base.wildlifeEventIds,
      events: base.events,
      shootingSessions: base.shootingSessions,
      wildlifeActivity: base.wildlifeActivity,
      location: base.location,
      temperatureCelsius: base.temperatureCelsius,
      windSpeedMetersPerSecond: base.windSpeedMetersPerSecond,
      windDirectionDegrees: base.windDirectionDegrees,
      visibilityKilometers: base.visibilityKilometers,
      precipitationMillimeters: base.precipitationMillimeters,
      cloudCoverPercent: base.cloudCoverPercent,
      airQualityIndex: base.airQualityIndex,
      airQualityCategory: base.airQualityCategory,
      primaryPollutant: base.primaryPollutant,
      airQualityObservedAt: base.airQualityObservedAt,
      airQualityStale: base.airQualityStale,
      solarElevationDegrees: base.solarElevationDegrees,
      solarAzimuthDegrees: base.solarAzimuthDegrees,
      sunrise: base.sunrise,
      sunset: base.sunset,
      isStale: stale,
      remoteGeneratedAt: base.remoteGeneratedAt,
      dataFreshness: stale
          ? ContextDataFreshness.stale
          : ContextDataFreshness.fresh,
      moonPhase: base.moonPhase,
      moonIllumination: base.moonIllumination,
      routeMode: base.routeMode,
      routeStage: base.routeStage,
      allowedActions: base.allowedActions,
      serverManifest: base.serverManifest,
      entries: base.entries,
      canonicalEntriesPresent: base.canonicalEntriesPresent,
    );

ContextSnapshot _snapshotWithSafety(
  DateTime observedAt, {
  String safetyId = 'thunderstorm',
}) {
  final base = ContextFixtures.lakeSunset(observedAt: observedAt);
  final event = context.ContextEvent(
    id: safetyId,
    channel: context.ContextEventChannel.safety,
    source: context.ContextEventSource.weather,
    observedAt: observedAt,
    expiresAt: observedAt.add(const Duration(minutes: 10)),
    confidence: .95,
    safetyLevel: context.ContextSafetyLevel.warning,
    allowedAction: context.ContextAction.openSafetyDetail,
  );
  return ContextSnapshot(
    id: base.id,
    observedAt: observedAt,
    expiresAt: base.expiresAt,
    primaryScene: base.primaryScene,
    sceneContext: base.sceneContext,
    dayPhase: base.dayPhase,
    weather: base.weather,
    activeRoute: base.activeRoute,
    opportunityIds: base.opportunityIds,
    safetyEventIds: [safetyId],
    wildlifeEventIds: base.wildlifeEventIds,
    events: [...base.events, event],
    shootingSessions: base.shootingSessions,
    location: base.location,
    temperatureCelsius: base.temperatureCelsius,
    windSpeedMetersPerSecond: base.windSpeedMetersPerSecond,
    visibilityKilometers: base.visibilityKilometers,
    precipitationMillimeters: base.precipitationMillimeters,
    cloudCoverPercent: base.cloudCoverPercent,
    solarElevationDegrees: base.solarElevationDegrees,
    sunrise: base.sunrise,
    sunset: base.sunset,
    allowedActions: const [context.ContextAction.openSafetyDetail],
  );
}
