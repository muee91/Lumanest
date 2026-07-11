import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';

void main() {
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

    await tester.tap(find.text('我的'));
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
