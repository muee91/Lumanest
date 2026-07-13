import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/features/inspiration/presentation/inspiration_page.dart';

void main() {
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
}

Widget _app({required bool disableAnimations}) {
  return ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: InspirationPage(
          snapshotAsync: AsyncValue.data(ContextFixtures.lakeSunset()),
        ),
      ),
    ),
  );
}
