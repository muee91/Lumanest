import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/features/inspiration/presentation/inspiration_page.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';

void main() {
  testWidgets('error state exposes retry and manual location recovery', (
    tester,
  ) async {
    var retries = 0;
    var manualSelections = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: InspirationPage(
            snapshotAsync: AsyncError(StateError('offline'), StackTrace.empty),
            onRetry: () => retries++,
            onSelectManualLocation: () => manualSelections++,
          ),
        ),
      ),
    );

    expect(find.text('暂时无法读取此刻的创作线索'), findsOneWidget);
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
          home: InspirationPage(
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

  testWidgets('quiet context keeps local creative prompts available', (
    tester,
  ) async {
    var explorations = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: InspirationPage(
            snapshotAsync: AsyncValue.data(ContextFixtures.quietCity()),
            onExplore: () => explorations++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('inspiration-bottle')), findsOneWidget);
    expect(find.text('抽一张'), findsOneWidget);
    expect(explorations, 0);
  });

  testWidgets('bottle keeps a subtle idle ticker when motion is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: false));

    expect(find.byKey(const Key('inspiration-bottle')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('system reduced motion renders a static bottle', (tester) async {
    await tester.pumpWidget(_app(disableAnimations: true));

    expect(find.byKey(const Key('inspiration-bottle')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'first screen keeps the bottle and draw as the only protagonists',
    (tester) async {
      await tester.pumpWidget(_app(disableAnimations: true));
      await tester.pump();

      expect(find.byKey(const Key('inspiration-bottle')), findsOneWidget);
      expect(find.text('抽一张'), findsOneWidget);
      // The explanatory header row and note count are gone.
      expect(find.textContaining(' 张'), findsNothing);
      // No drawn note hero yet.
      expect(
        find.byKey(const Key('selected-inspiration-reflection')),
        findsNothing,
      );
    },
  );

  testWidgets('drawing changes the selected note without changing facts', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));

    expect(
      find.byKey(const Key('selected-inspiration-reflection')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('inspiration-bottle')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('selected-inspiration-reflection')),
      findsOneWidget,
    );
    expect(find.text('找倒影🪞'), findsWidgets);
  });

  testWidgets('details stay collapsed after drawing and expand on demand', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('draw-inspiration-note')));
    await tester.pump(const Duration(milliseconds: 400));

    // The peek affordance is visible, but the long detail and actions are not.
    expect(find.text('详情'), findsOneWidget);
    expect(find.text('风正在变小，去湖岸找一段干净的水面。'), findsNothing);
    expect(find.text('收藏纸条'), findsNothing);

    await tester.tap(find.text('详情'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('风正在变小，去湖岸找一段干净的水面。'), findsOneWidget);
    expect(find.text('查看机会'), findsOneWidget);
    expect(find.text('收藏纸条'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('a factual note is labelled as an established opportunity', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('draw-inspiration-note')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('详情'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已成立机会'), findsOneWidget);
    expect(find.text('查看机会'), findsOneWidget);
  });

  testWidgets('a creative note is labelled as a creative direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: InspirationPage(
              snapshotAsync: AsyncValue.data(ContextFixtures.quietCity()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('draw-inspiration-note')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('详情'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('创作方向'), findsOneWidget);
    expect(find.text('去探索'), findsOneWidget);
    // Creative prompts never claim an established opportunity.
    expect(find.text('已成立机会'), findsNothing);
  });

  testWidgets('drawing again collapses the detail panel', (tester) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('draw-inspiration-note')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('详情'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.byKey(const Key('draw-inspiration-note')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('详情'), findsOneWidget);
    expect(find.text('风正在变小，去湖岸找一段干净的水面。'), findsNothing);
  });

  testWidgets('saves only the selected note to the local library', (
    tester,
  ) async {
    final store = _MemoryLibraryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userLibraryStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: InspirationPage(
              snapshotAsync: AsyncValue.data(
                ContextFixtures.lakeSunset(observedAt: DateTime.now()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('draw-inspiration-note')));
    await tester.pump(const Duration(milliseconds: 400));
    // Details are on demand: expand before saving.
    await tester.tap(find.text('详情'));
    await tester.pump(const Duration(milliseconds: 300));

    final saveButton = find.text('收藏纸条');
    final saveControl = tester.widget<TextButton>(
      find.ancestor(of: saveButton, matching: find.byType(TextButton)),
    );
    saveControl.onPressed!();
    await tester.pump();

    expect(store.value.savedNotes, hasLength(1));
    expect(store.value.savedNotes.single.displayLabel, '找倒影🪞');
    expect(find.text('已收藏'), findsOneWidget);
  });
}

Widget _app({required bool disableAnimations}) {
  return ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: InspirationPage(
          snapshotAsync: AsyncValue.data(
            ContextFixtures.lakeSunset(observedAt: DateTime.now()),
          ),
        ),
      ),
    ),
  );
}

class _MemoryLibraryStore implements UserLibraryStore {
  UserLibraryState value = const UserLibraryState();

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}
