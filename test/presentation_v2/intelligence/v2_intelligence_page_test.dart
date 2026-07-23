import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/presentation_v2/intelligence/v2_intelligence_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('contracts only the inspiration stage while typing', (
    tester,
  ) async {
    await _pump(tester);

    final stage = find.byKey(
      const Key('v2-intelligence-inspiration-stage'),
    );
    final before = tester.getSize(stage).height;
    expect(before, greaterThan(200));
    expect(find.byKey(const Key('v2-intelligence-assistant-stage')), findsOne);
    expect(find.byKey(const Key('v2-intelligence-composer')), findsOne);

    await tester.tap(find.byKey(const Key('v2-intelligence-input')));
    await tester.pumpAndSettle();

    final after = tester.getSize(stage).height;
    expect(after, lessThanOrEqualTo(110));
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

    expect(
      find.byKey(const Key('v2-intelligence-compact-inspiration')),
      findsOne,
    );
    expect(
      find.byKey(const Key('v2-intelligence-assistant-message')),
      findsOne,
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const Key('v2-intelligence-composer')), findsOne);
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
