import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart' as context;
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
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

  testWidgets('decision hero keeps its label on the stable readable surface', (
    tester,
  ) async {
    final snapshot = ContextFixtures.quietCity();
    final theme = LumaNestTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: TodayPage(snapshotAsync: AsyncData(snapshot)),
      ),
    );

    final label = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data?.endsWith('判断') == true,
      ),
    );
    expect(label.style?.color, theme.colorScheme.onSurfaceVariant);
  });

  testWidgets('labels a manual reference place as non-live', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(
          snapshotAsync: AsyncData(ContextFixtures.quietCity()),
          locationDisplay: const EnvironmentLocationDisplay(
            label: '海宁市',
            source: EnvironmentLocationSource.manual,
          ),
        ),
      ),
    );

    expect(find.text('海宁市 · 手动地点 · 非实时'), findsOneWidget);
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

    testWidgets('permanent location denial opens app settings', (tester) async {
      var retries = 0;
      var settingsOpened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncError(
              const EnvironmentLoadFailure(
                EnvironmentFailureKind.location,
                cause: LocationRepositoryFailure(
                  LocationFailureKind.permissionDeniedForever,
                ),
              ),
              StackTrace.empty,
            ),
            onRetry: () => retries++,
            onOpenAppSettings: () => settingsOpened++,
          ),
        ),
      );

      expect(find.text('重试'), findsNothing);
      await tester.tap(find.text('打开设置'));
      expect(settingsOpened, 1);
      expect(retries, 0);
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
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncData(snapshot),
            manifest: ManifestPolicy.build(snapshot, now: snapshot.observedAt),
          ),
        ),
      );

      expect(find.text('数据已过期'), findsNothing);
      expect(find.textContaining('光线平静'), findsOneWidget);
      expect(find.text('天气数据：和风天气'), findsNothing);
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

    testWidgets('missing environment metrics reserve no placeholder strip', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 7, 15, 8);
      final snapshot = ContextSnapshot(
        id: 'no-metrics',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
      );

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.text('天气数据：和风天气'), findsNothing);
      expect(find.textContaining('--'), findsNothing);
    });

    testWidgets('unrelated metrics do not compete with the main conclusion', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 7, 15, 8);
      final snapshot = ContextSnapshot(
        id: 'partial-metrics',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        temperatureCelsius: 21.4,
      );

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.text('21°'), findsNothing);
      expect(find.text('天气数据：和风天气'), findsNothing);
      expect(find.textContaining('--'), findsNothing);
    });

    testWidgets('AQI without an active decision keeps no visual slot', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 7, 15, 8);
      ContextSnapshot snapshot({required bool stale}) => ContextSnapshot(
        id: 'air-quality-$stale',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        airQualityIndex: 168,
        airQualityCategory: '中度污染',
        airQualityObservedAt: now,
        airQualityStale: stale,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(snapshotAsync: AsyncData(snapshot(stale: false))),
        ),
      );
      expect(find.text('168'), findsNothing);
      expect(find.text('AQI · 中度污染'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(snapshotAsync: AsyncData(snapshot(stale: true))),
        ),
      );
      expect(find.text('168'), findsNothing);
      expect(find.textContaining('AQI'), findsNothing);
    });

    testWidgets('lake sunset renders one primary opportunity', (tester) async {
      final snapshot = ContextFixtures.lakeSunset();

      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncData(snapshot),
            manifest: ManifestPolicy.build(snapshot, now: snapshot.observedAt),
          ),
        ),
      );

      expect(find.byKey(const Key('primary-opportunity')), findsOneWidget);
      expect(find.text('倒影条件改善'), findsOneWidget);
    });

    testWidgets('tapping an opportunity invokes the whitelisted action', (
      tester,
    ) async {
      ManifestItem? tapped;
      final snapshot = ContextFixtures.lakeSunset();
      await tester.pumpWidget(
        MaterialApp(
          home: TodayPage(
            snapshotAsync: AsyncData(snapshot),
            manifest: ManifestPolicy.build(snapshot, now: snapshot.observedAt),
            onManifestAction: (item) => tapped = item,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('primary-opportunity')));

      expect(tapped?.id, 'reflection');
    });

    testWidgets('safety content is separate from inspiration', (tester) async {
      final now = DateTime.now().toUtc();
      final snapshot = ContextSnapshot(
        id: 'today-safety',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        safetyEventIds: const ['thunderstorm'],
        events: [
          context.ContextEvent(
            id: 'thunderstorm',
            channel: context.ContextEventChannel.safety,
            source: context.ContextEventSource.weather,
            observedAt: now,
            expiresAt: now.add(const Duration(minutes: 10)),
            confidence: 0.9,
            geoScope: context.ContextGeoScope.point,
            safetyLevel: context.ContextSafetyLevel.warning,
            allowedAction: context.ContextAction.openSafety,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(home: TodayPage(snapshotAsync: AsyncData(snapshot))),
      );

      expect(find.byKey(const Key('safety-region')), findsOneWidget);
      expect(find.text('雷暴正在接近'), findsOneWidget);
      expect(find.textContaining('天气数据'), findsOneWidget);
      expect(find.textContaining('警告'), findsOneWidget);
      expect(find.textContaining('当前地点'), findsOneWidget);
      expect(find.textContaining('更新'), findsOneWidget);
      expect(find.textContaining('前有效'), findsOneWidget);

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
