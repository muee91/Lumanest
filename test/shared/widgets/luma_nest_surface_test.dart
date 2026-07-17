import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/design/luma_nest_colors.dart';
import 'package:luma_nest/src/design/luma_nest_text_styles.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_surface.dart';

void main() {
  group('LumaNestSurface tones', () {
    testWidgets('mist is opaque and borderless without glass blur', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LumaNestSurface(
              tone: LumaNestSurfaceTone.mist,
              child: const Text('content'),
            ),
          ),
        ),
      );

      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'mist must not use glass blur',
      );
      final decoration = _surfaceDecoration(tester);
      expect(decoration.border, isNull, reason: 'mist must not paint a border');
      expect((decoration.color!.a * 255).round(), closeTo(0.82 * 255, 1));
    });

    testWidgets('solid is opaque and borderless for settings groups', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LumaNestSurface(
              tone: LumaNestSurfaceTone.solid,
              child: const Text('settings'),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      final decoration = _surfaceDecoration(tester);
      expect(
        decoration.border,
        isNull,
        reason: 'solid must not paint a border',
      );
    });

    testWidgets('mapOverlay keeps glass blur and a hairline border', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LumaNestSurface(
              tone: LumaNestSurfaceTone.mapOverlay,
              child: const Text('map'),
            ),
          ),
        ),
      );

      expect(
        find.byType(BackdropFilter),
        findsOneWidget,
        reason: 'mapOverlay is the only glass content surface',
      );
      final decoration = _surfaceDecoration(tester);
      expect(decoration.border, isNotNull);
    });

    testWidgets('default border radius is the regular tier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LumaNestSurface(child: const Text('r'))),
        ),
      );

      final decoration = _surfaceDecoration(tester);
      expect(
        decoration.borderRadius?.resolve(TextDirection.ltr).topLeft.x,
        LumaNestRadii.regular,
      );
    });
  });

  group('LumaNestEyebrow', () {
    testWidgets('renders the label on the brand face', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LumaNestEyebrow(label: '探索')),
        ),
      );

      final text = tester.widget<Text>(find.text('探索'));
      expect(text.style?.fontFamily, LumaNestTextStyles.brandFamily);
    });
  });
}

BoxDecoration _surfaceDecoration(WidgetTester tester) {
  final containers = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
  for (final box in containers) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.borderRadius != null) {
      return decoration;
    }
  }
  throw StateError('No surface BoxDecoration found');
}
