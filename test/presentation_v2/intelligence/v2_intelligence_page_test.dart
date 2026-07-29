import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/presentation_v2/intelligence/v2_intelligence_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('keeps the conversation entry visible while typing', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const Key('v2-intelligence-welcome')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-assistant-stage')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-composer')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-note-0')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-note-1')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-note-2')), findsNothing);

    await tester.tap(find.byKey(const Key('v2-intelligence-input')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('v2-intelligence-welcome')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-assistant-stage')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-composer')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-input')), findsOne);
  });

  testWidgets('interprets an inspiration in place without another sheet', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('v2-intelligence-note-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('v2-intelligence-welcome')), findsNothing);
    expect(
      find.byKey(const Key('v2-intelligence-assistant-message')),
      findsOne,
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const Key('v2-intelligence-composer')), findsOne);
  });

  testWidgets('answers current photography questions from the fresh snapshot', (
    tester,
  ) async {
    final snapshot = ContextFixtures.lakeSunset(observedAt: DateTime.now());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [assistantModelProvider.overrideWithValue(null)],
        child: MaterialApp(home: V2IntelligencePage(initialSnapshot: snapshot)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('今天适合拍什么？'));
    await tester.pumpAndSettle();

    expect(find.textContaining('湖岸晚间窗口'), findsOneWidget);
    expect(find.textContaining('当前多云'), findsOneWidget);
    expect(find.text('栖光规则 · 当前数据'), findsOneWidget);
  });

  testWidgets('keeps the conversation composer on the light canvas', (
    tester,
  ) async {
    await _pump(tester);

    final surface = tester.widget<Container>(
      find.byKey(const Key('v2-intelligence-composer-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFF5F5F1));
  });
}

Future<void> _pump(WidgetTester tester) async {
  final now = DateTime.utc(2026, 7, 24, 10);
  final snapshot = ContextSnapshot(
    id: 'intelligence-layout-fixture',
    observedAt: now,
    expiresAt: now.add(const Duration(hours: 2)),
    primaryScene: SceneType.city,
    dayPhase: DayPhase.day,
    weather: WeatherType.cloudy,
    activeRoute: false,
    location: const GeoPoint(latitude: 30.25, longitude: 120.15),
    temperatureCelsius: 24,
    cloudCoverPercent: 48,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [assistantModelProvider.overrideWithValue(null)],
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: V2IntelligencePage(initialSnapshot: snapshot),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
