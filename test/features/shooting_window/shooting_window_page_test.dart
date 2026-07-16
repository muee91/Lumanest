import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/features/shooting_window/presentation/shooting_window_page.dart';

void main() {
  testWidgets('error state exposes retry and manual location recovery', (
    tester,
  ) async {
    var retries = 0;
    var manualSelections = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShootingWindowPage(
            snapshotAsync: AsyncError(StateError('offline'), StackTrace.empty),
            onRetry: () => retries++,
            onSelectManualLocation: () => manualSelections++,
          ),
        ),
      ),
    );

    expect(find.text('暂时无法读取拍摄窗口'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.tap(find.text('手动选择地点'));
    expect(retries, 1);
    expect(manualSelections, 1);
  });

  testWidgets('permanent location denial offers app settings', (tester) async {
    var settingsOpened = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShootingWindowPage(
            snapshotAsync: AsyncError(
              const EnvironmentLoadFailure(
                EnvironmentFailureKind.location,
                cause: LocationRepositoryFailure(
                  LocationFailureKind.permissionDeniedForever,
                ),
              ),
              StackTrace.empty,
            ),
            onOpenAppSettings: () => settingsOpened++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开设置'));
    expect(settingsOpened, 1);
  });

  testWidgets('renders calculated windows and the terrain limitation', (
    tester,
  ) async {
    final sunrise = DateTime.utc(2026, 7, 13, 21);
    final sunset = DateTime.utc(2026, 7, 14, 11);
    final snapshot = ContextSnapshot(
      id: 'window-page',
      observedAt: sunset.subtract(const Duration(minutes: 10)),
      expiresAt: sunset,
      primaryScene: SceneType.city,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: false,
      sunrise: sunrise,
      sunset: sunset,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShootingWindowPage(snapshotAsync: AsyncData(snapshot)),
        ),
      ),
    );

    expect(find.text('晨光窗口'), findsOneWidget);
    expect(find.text('落日窗口'), findsOneWidget);
    expect(find.text('蓝调窗口'), findsOneWidget);
    expect(find.textContaining('不包含山体'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('renders an established opportunity instead of solar fallback', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 17, 10);
    final snapshot = ContextSnapshot(
      id: 'opportunity-window',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      activeRoute: false,
      solarAzimuthDegrees: 270,
      photographyOpportunities: [
        PhotographyOpportunity(
          id: 'sunset-window',
          title: '晚霞窗口',
          startsAt: now.add(const Duration(minutes: 10)),
          peaksAt: now.add(const Duration(minutes: 25)),
          expiresAt: now.add(const Duration(minutes: 45)),
          confidence: .9,
          requiredCapabilities: const ['tripod'],
          evidence: const [
            PhotographyEvidence(
              id: 'clouds',
              kind: PhotographyEvidenceKind.weather,
              statement: '云层变化已成立。',
              confidence: .8,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShootingWindowPage(
            snapshotAsync: AsyncData(snapshot),
            now: () => now,
          ),
        ),
      ),
    );

    expect(find.text('晚霞窗口'), findsOneWidget);
    expect(find.byKey(const Key('opportunity-countdown')), findsOneWidget);
    expect(find.byKey(const Key('start-watching')), findsOneWidget);
    expect(find.text('今日参考时间轴'), findsNothing);
    expect(find.text('光线方向 西'), findsOneWidget);
  });

  testWidgets(
    'uses a valid routed opportunity ID instead of the first window',
    (tester) async {
      final now = DateTime.utc(2026, 7, 17, 10);
      PhotographyOpportunity opportunity(String id, String title) =>
          PhotographyOpportunity(
            id: id,
            title: title,
            startsAt: now.add(const Duration(minutes: 10)),
            peaksAt: now.add(const Duration(minutes: 20)),
            expiresAt: now.add(const Duration(minutes: 30)),
            confidence: .8,
            evidence: const [
              PhotographyEvidence(
                id: 'weather',
                kind: PhotographyEvidenceKind.weather,
                statement: '条件已成立。',
                confidence: .8,
              ),
            ],
          );
      final snapshot = ContextSnapshot(
        id: 'routed-window',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 20)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.clear,
        activeRoute: false,
        photographyOpportunities: [
          opportunity('photo-first', '第一窗口'),
          opportunity('photo-target', '指定窗口'),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ShootingWindowPage(
              snapshotAsync: AsyncData(snapshot),
              now: () => now,
              initialOpportunityId: 'photo-target',
            ),
          ),
        ),
      );

      expect(find.text('指定窗口'), findsWidgets);
      expect(find.text('第一窗口'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChoiceChip),
          matching: find.text('指定窗口'),
        ),
        findsOneWidget,
      );
      final selected = tester.widget<ChoiceChip>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ChoiceChip &&
              widget.label is Text &&
              (widget.label as Text).data == '指定窗口',
        ),
      );
      expect(selected.selected, isTrue);
    },
  );

  testWidgets('starts foreground watching and exposes local result feedback', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 17, 10);
    var refreshes = 0;
    final snapshot = ContextSnapshot(
      id: 'watching-window',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      activeRoute: false,
      photographyOpportunities: [
        PhotographyOpportunity(
          id: 'watch-this',
          title: '守候测试',
          startsAt: now,
          peaksAt: now.add(const Duration(minutes: 10)),
          expiresAt: now.add(const Duration(minutes: 30)),
          confidence: .9,
          evidence: const [
            PhotographyEvidence(
              id: 'weather',
              kind: PhotographyEvidenceKind.weather,
              statement: '条件已成立。',
              confidence: .8,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShootingWindowPage(
            snapshotAsync: AsyncData(snapshot),
            now: () => now,
            onRefresh: () async => refreshes += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('start-watching')));
    await tester.pump();
    expect(find.byKey(const Key('end-watching')), findsOneWidget);
    expect(find.text('拍到了'), findsOneWidget);
    await tester.tap(find.byKey(const Key('refresh-watching')));
    await tester.pump();
    expect(refreshes, 1);
  });
}
