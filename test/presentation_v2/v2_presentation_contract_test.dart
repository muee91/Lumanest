import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/presentation_v2/opportunity/v2_opportunity_page.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_opportunity_object.dart';

void main() {
  testWidgets('V2 Today keeps the opportunity as one Hero object', (
    tester,
  ) async {
    final snapshot = ContextFixtures.lakeSunset(observedAt: DateTime.now());
    final session = snapshot.shootingSessions.single;
    await tester.pumpWidget(LumaNestApp(initialContext: snapshot));
    await tester.pump();

    expect(find.byType(V2OpportunityObject), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'v2-opportunity:${session.id}',
    );

    await tester.tap(find.byType(V2OpportunityObject));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(V2OpportunityPage), findsOneWidget);
    expect(find.text('时间在对象内部展开'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'v2-opportunity:${session.id}',
    );
  });

  testWidgets('V2 shell exposes five semantic destinations', (tester) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.text('今日'), findsOneWidget);
    for (final label in ['探索', '路线', '灵感', '我的']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(find.byKey(const Key('v2-bottom-navigation')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
