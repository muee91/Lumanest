import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_opportunity_object.dart';

void main() {
  testWidgets('V2 five-page shell stays usable at 360 x 800', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();
    expect(tester.takeException(), isNull);

    for (final label in ['探索', '路线', '灵感', '我的']) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(
        tester.takeException(),
        isNull,
        reason: '$label must not overflow',
      );
    }
  });

  testWidgets('V2 Today and Opportunity tolerate enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final snapshot = ContextFixtures.lakeSunset(observedAt: DateTime.now());
    await tester.pumpWidget(LumaNestApp(initialContext: snapshot));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(V2OpportunityObject));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(find.text('时间在对象内部展开'), findsOneWidget);
  });
}
