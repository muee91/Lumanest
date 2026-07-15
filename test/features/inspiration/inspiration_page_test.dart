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

  testWidgets('drawing changes the selected note without changing facts', (
    tester,
  ) async {
    await tester.pumpWidget(_app(disableAnimations: true));

    expect(
      find.byKey(const Key('selected-inspiration-reflection')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('inspiration-bottle')));
    await tester.pump();

    expect(
      find.byKey(const Key('selected-inspiration-blue-hour')),
      findsOneWidget,
    );
    expect(find.text('找倒影🪞'), findsWidgets);
    expect(find.text('蓝调了🌆'), findsWidgets);
  });

  testWidgets('saves only the selected creative note to the local library', (
    tester,
  ) async {
    final store = _MemoryLibraryStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userLibraryStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: InspirationPage(
            snapshotAsync: AsyncValue.data(
              ContextFixtures.lakeSunset(observedAt: DateTime.now()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final saveButton = find.text('收藏这张纸条');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
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
