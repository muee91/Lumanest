import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart' as context;
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';

void main() {
  final now = DateTime.now().toUtc();

  testWidgets('safety starts expanded and collapse reveals the primary card', (
    tester,
  ) async {
    final snapshot = _snapshotWithSafety(now);
    await tester.pumpWidget(_host(snapshot));
    await tester.pump();

    expect(find.byKey(const Key('v2-safety-object')), findsOneWidget);
    expect(find.byKey(const Key('v2-safety-collapse')), findsOneWidget);
    expect(find.byKey(const Key('v2-safety-strip')), findsNothing);
    expect(find.text('这个窗口值得你提前到场。'), findsNothing);

    await tester.tap(find.byKey(const Key('v2-safety-collapse')));
    await tester.pump();

    expect(find.byKey(const Key('v2-safety-object')), findsNothing);
    expect(find.byKey(const Key('v2-safety-strip')), findsOneWidget);
    expect(find.text('雷暴正在接近'), findsOneWidget);
    expect(find.text('这个窗口值得你提前到场。'), findsOneWidget);
  });

  testWidgets('a refreshed composition expands a previously collapsed alert', (
    tester,
  ) async {
    final first = _snapshotWithSafety(now);
    await tester.pumpWidget(_host(first));
    await tester.pump();
    await tester.tap(find.byKey(const Key('v2-safety-collapse')));
    await tester.pump();
    expect(find.byKey(const Key('v2-safety-strip')), findsOneWidget);

    await tester.pumpWidget(
      _host(_snapshotWithSafety(now.add(const Duration(minutes: 1)))),
    );
    await tester.pump();

    expect(find.byKey(const Key('v2-safety-object')), findsOneWidget);
    expect(find.byKey(const Key('v2-safety-strip')), findsNothing);
  });

  testWidgets(
    'a new alert expands even when the composition revision is equal',
    (tester) async {
      await tester.pumpWidget(_host(_snapshotWithSafety(now)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('v2-safety-collapse')));
      await tester.pump();

      await tester.pumpWidget(
        _host(_snapshotWithSafety(now, safetyId: 'strong-wind')),
      );
      await tester.pump();

      expect(find.byKey(const Key('v2-safety-object')), findsOneWidget);
      expect(find.text('当前风力较强'), findsOneWidget);
      expect(find.byKey(const Key('v2-safety-strip')), findsNothing);
    },
  );
}

Widget _host(ContextSnapshot snapshot) => ProviderScope(
  overrides: [currentTimeProvider.overrideWithValue(() => snapshot.observedAt)],
  child: MaterialApp(home: V2TodayPage(initialSnapshot: snapshot)),
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
