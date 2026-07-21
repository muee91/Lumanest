import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/presentation_v2/inspiration/v2_inspiration_page.dart';

void main() {
  testWidgets('AI entry is a text conversation without unsupported controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentSnapshotProvider.overrideWith(
            _FixedEnvironmentController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: V2InspirationPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('问栖光'), findsOneWidget);
    expect(find.text('摄影对话'), findsOneWidget);
    expect(find.text('发消息给栖光'), findsOneWidget);
    expect(find.text('想去哪里？'), findsNothing);
    expect(find.text('我可以帮你发现附近灵感、活动、路线'), findsNothing);
    expect(find.byIcon(CupertinoIcons.plus), findsNothing);
    expect(find.byIcon(CupertinoIcons.mic_fill), findsNothing);
    expect(find.byKey(const Key('v2-inspiration-send')), findsOneWidget);
  });
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() async =>
      ContextFixtures.quietCity(observedAt: DateTime.now());
}
