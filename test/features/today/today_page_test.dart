import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/today/presentation/today_page.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';

void main() {
  testWidgets('uses validated narrative summary when available', (
    tester,
  ) async {
    final snapshot = ContextFixtures.lakeSunset();
    final narrative = ManifestNarrative(
      summary: '湖面正在安静下来，可以等等倒影。',
      source: ManifestNarrativeSource.model,
      generatedAt: DateTime.utc(2026, 7, 11, 10),
      expiresAt: DateTime.utc(2026, 7, 11, 10, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          snapshotAsync: AsyncData(snapshot),
          narrativeAsync: AsyncData(narrative),
        ),
      ),
    );

    expect(find.text(narrative.summary), findsOneWidget);
  });

  group('TodayPage async states', () {
    testWidgets('loading state shows a loading indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TodayPage(snapshotAsync: AsyncLoading())),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('config missing error shows message and retry button', (
      tester,
    ) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncError(
              const EnvironmentLoadFailure(
                EnvironmentFailureKind.configMissing,
              ),
              StackTrace.empty,
            ),
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.textContaining('环境配置'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('location error shows message and retry action', (
      tester,
    ) async {
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncError(
              const EnvironmentLoadFailure(EnvironmentFailureKind.location),
              StackTrace.empty,
            ),
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.textContaining('位置'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('location error offers a manual location recovery action', (
      tester,
    ) async {
      var selectedManualLocation = false;
      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncError(
              const EnvironmentLoadFailure(EnvironmentFailureKind.location),
              StackTrace.empty,
            ),
            onSelectManualLocation: () => selectedManualLocation = true,
          ),
        ),
      );

      await tester.tap(find.text('手动选择地点'));
      expect(selectedManualLocation, isTrue);
    });

    testWidgets('stale cached snapshot shows stale label', (tester) async {
      final staleSnapshot = ContextFixtures.quietCity().asStale();

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(staleSnapshot))),
      );

      expect(find.text('数据已过期'), findsOneWidget);
    });

    testWidgets('live manifest renders summary and no stale label', (
      tester,
    ) async {
      final snapshot = ContextFixtures.quietCity();

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.text('数据已过期'), findsNothing);
      expect(find.textContaining('光线平静'), findsOneWidget);
      expect(find.text('天气数据：和风天气'), findsOneWidget);
    });

    testWidgets('quiet context renders no opportunity placeholder', (
      tester,
    ) async {
      final snapshot = ContextFixtures.quietCity();

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.byKey(const Key('primary-opportunity')), findsNothing);
      expect(find.byKey(const Key('secondary-opportunities')), findsNothing);
      expect(find.text('探索附近'), findsOneWidget);
    });

    testWidgets('lake sunset renders one primary opportunity', (tester) async {
      final snapshot = ContextFixtures.lakeSunset();

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.byKey(const Key('primary-opportunity')), findsOneWidget);
      expect(find.text('倒影条件改善'), findsOneWidget);
    });

    testWidgets('tapping an opportunity invokes the whitelisted action', (
      tester,
    ) async {
      ManifestItem? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncData(ContextFixtures.lakeSunset()),
            onManifestAction: (item) => tapped = item,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('primary-opportunity')));

      expect(tapped?.id, 'reflection');
    });

    testWidgets('safety content is separate from inspiration', (tester) async {
      final snapshot = ContextSnapshot(
        id: 'today-safety',
        observedAt: DateTime.utc(2026, 7, 11),
        expiresAt: DateTime.utc(2026, 7, 11, 0, 10),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        safetyEventIds: const ['thunderstorm'],
      );

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.byKey(const Key('safety-region')), findsOneWidget);
      expect(find.text('雷暴正在接近'), findsOneWidget);

      expect(find.byKey(const Key('inspiration-preview')), findsNothing);
    });

    testWidgets('error without retry callback shows no retry button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncError(
              EnvironmentLoadFailure(EnvironmentFailureKind.configMissing),
              StackTrace.empty,
            ),
          ),
        ),
      );

      expect(find.text('重试'), findsNothing);
    });
  });
}
