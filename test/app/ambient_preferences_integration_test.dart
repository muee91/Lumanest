import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';

void main() {
  testWidgets('system animation setting makes the ambient canvas static', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceMotion,
      isTrue,
    );
  });

  testWidgets('navigation disposes the ambient field outside Today', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.byType(AmbientCanvas), findsOneWidget);
    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).intensity,
      1.0,
    );

    await tester.tap(
      find.bySemanticsLabel('栖光：问问题或抽取灵感'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(AmbientCanvas), findsNothing);

    // Intelligence is an overlay; closing restores the originating Today page.
    await tester.tap(find.bySemanticsLabel('关闭栖光'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AmbientCanvas), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('路线'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AmbientCanvas), findsNothing);

    await tester.tap(find.bySemanticsLabel('我的'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AmbientCanvas), findsNothing);

    await tester.tap(find.bySemanticsLabel('今日'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AmbientCanvas), findsOneWidget);
    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).intensity,
      1.0,
    );
  });

  testWidgets('V2 privacy controls global accessibility rendering', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.byType(AmbientCanvas), findsOneWidget);
    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceMotion,
      isFalse,
    );
    expect(
      tester
          .widget<AmbientCanvas>(find.byType(AmbientCanvas))
          .showWeatherTexture,
      isTrue,
    );

    final normalScheme = Theme.of(
      tester.element(find.byType(Scaffold).first),
    ).colorScheme;
    expect(normalScheme, LumaNestTheme.light.colorScheme);

    await tester.tap(find.bySemanticsLabel('我的'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私与感受'));
    await tester.pumpAndSettle();
    final highContrastObject = find.ancestor(
      of: find.text('高对比度'),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(highContrastObject.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final highContrastScheme = Theme.of(
      tester.element(find.text('高对比度')),
    ).colorScheme;
    expect(highContrastScheme, LumaNestTheme.highContrastLight.colorScheme);

    final reduceMotionObject = find.ancestor(
      of: find.text('减少动态'),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(reduceMotionObject.first);
    await tester.pump();
    expect(find.byType(AmbientCanvas), findsNothing);

    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('今日'));
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceMotion,
      isTrue,
    );
  });
}
