import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_brand_mark.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_loading_placeholder.dart';

void main() {
  group('LumaNestLoadingPlaceholder', () {
    testWidgets('shows brand mark, label and animated indicator by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LumaNestLoadingPlaceholder(label: '地图加载中')),
        ),
      );

      expect(find.byType(LumaNestBrandMark), findsOneWidget);
      expect(find.text('地图加载中'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('falls back to a static ring when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const MaterialApp(
            home: Scaffold(body: LumaNestLoadingPlaceholder()),
          ),
        ),
      );

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'reduce motion must not animate the indicator',
      );
      // A static ring is rendered as a circular bordered box.
      final decorated = tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      );
      final hasRing = decorated.any((box) {
        final d = box.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });
      expect(hasRing, isTrue);
    });

    testWidgets('exposes a loading semantics label even without text', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LumaNestLoadingPlaceholder())),
      );

      final semantics = tester.getSemantics(
        find.byType(LumaNestLoadingPlaceholder),
      );
      expect(semantics.label, '正在加载');
    });
  });
}
