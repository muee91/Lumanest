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

  testWidgets('profile preferences control the global ambient canvas', (
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

    await tester.tap(find.text('我的'));
    await tester.pump();
    final highContrastTile = find.ancestor(
      of: find.text('高对比度'),
      matching: find.byType(SwitchListTile),
    );
    await tester.ensureVisible(highContrastTile);
    await tester.tap(highContrastTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SwitchListTile>(highContrastTile).value, isTrue);
    final highContrastScheme = Theme.of(
      tester.element(find.text('高对比度')),
    ).colorScheme;
    expect(highContrastScheme, LumaNestTheme.highContrastLight.colorScheme);

    await tester.tap(find.text('节能'));
    await tester.pump();
    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceMotion,
      isTrue,
    );
    expect(
      tester
          .widget<AmbientCanvas>(find.byType(AmbientCanvas))
          .showWeatherTexture,
      isTrue,
    );

    await tester.tap(find.text('静态'));
    await tester.pump();
    expect(
      tester
          .widget<AmbientCanvas>(find.byType(AmbientCanvas))
          .showWeatherTexture,
      isFalse,
    );

    await tester.tap(find.text('完整'));
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.text('减少动效'),
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceMotion,
      isTrue,
    );

    await tester.tap(
      find.ancestor(
        of: find.text('减少闪烁'),
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<AmbientCanvas>(find.byType(AmbientCanvas)).reduceFlashing,
      isTrue,
    );

    await tester.tap(
      find.ancestor(
        of: find.text('动态背景'),
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pump();

    expect(find.byType(AmbientCanvas), findsNothing);
  });
}
