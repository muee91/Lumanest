import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/features/today/presentation/today_page.dart';

void main() {
  testWidgets('quiet context renders no opportunity placeholder', (
    tester,
  ) async {
    final manifest = ManifestPolicy.build(ContextFixtures.quietCity());

    await tester.pumpWidget(MaterialApp(home: TodayPage(manifest: manifest)));

    expect(find.text(manifest.summary), findsOneWidget);
    expect(find.byKey(const Key('primary-opportunity')), findsNothing);
    expect(find.byKey(const Key('secondary-opportunities')), findsNothing);
    expect(find.text('探索附近'), findsOneWidget);
  });

  testWidgets('lake sunset renders one primary opportunity', (tester) async {
    final manifest = ManifestPolicy.build(ContextFixtures.lakeSunset());

    await tester.pumpWidget(MaterialApp(home: TodayPage(manifest: manifest)));

    expect(find.byKey(const Key('primary-opportunity')), findsOneWidget);
    expect(find.text('倒影条件改善'), findsOneWidget);
  });

  testWidgets('safety content is separate from inspiration', (tester) async {
    final manifest = ManifestPolicy.build(
      ContextSnapshot(
        id: 'today-safety',
        observedAt: DateTime.utc(2026, 7, 11),
        expiresAt: DateTime.utc(2026, 7, 11, 0, 10),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        safetyEventIds: const ['thunderstorm'],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: TodayPage(manifest: manifest)));

    expect(find.byKey(const Key('safety-region')), findsOneWidget);
    expect(find.text('雷暴正在接近'), findsOneWidget);

    final inspiration = tester.widget<Text>(
      find.byKey(const Key('inspiration-preview')),
    );
    expect(inspiration.data, isNot(contains('雷暴')));
  });
}
