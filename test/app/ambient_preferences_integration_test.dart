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

  testWidgets('navigation refreshes page-level ambient intensity', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    double intensity() =>
        tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).intensity;

    expect(intensity(), 1.0);

    await tester.tap(find.bySemanticsLabel('灵感'));
    await tester.pump();
    await tester.pump();
    expect(intensity(), 1.2);

    await tester.tap(find.bySemanticsLabel('路线'));
    await tester.pump();
    await tester.pump();
    expect(intensity(), 0.15);

    await tester.tap(find.bySemanticsLabel('我的'));
    await tester.pump();
    await tester.pump();
    expect(intensity(), 0.0);
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
    await tester.tap(find.text('隐私'));
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
    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceMotion,
      isTrue,
    );
  });
}
