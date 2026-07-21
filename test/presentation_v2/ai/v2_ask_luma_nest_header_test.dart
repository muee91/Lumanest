import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/presentation_v2/ai/v2_ask_luma_nest.dart';

void main() {
  testWidgets('assistant header stays simple and uses the Qiguang name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snapshot = ContextFixtures.quietCity();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showAskLumaNestSheet(context, snapshot: snapshot),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('问栖光'), findsOneWidget);
    expect(find.text('问 Luma'), findsNothing);
    expect(find.byIcon(CupertinoIcons.square_pencil), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
    await tester.pumpAndSettle();

    expect(find.text('新建对话'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.square_pencil), findsOneWidget);
  });
}
