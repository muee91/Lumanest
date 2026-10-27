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
    expect(find.text('拍摄时间轴'), findsOneWidget);
    expect(find.text('拍摄建议'), findsOneWidget);
    expect(find.text('查看依据'), findsOneWidget);
    expect(find.text('判断依据'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'v2-opportunity:${session.id}',
    );

    await tester.tap(find.text('查看依据'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('查看依据'), findsNothing);
    expect(find.text('收起依据'), findsOneWidget);
    expect(find.text('判断依据'), findsOneWidget);

    await tester.tap(find.byKey(const Key('v2-phase-node-1')));
    await tester.pump();
    expect(find.textContaining('倒影 ·'), findsOneWidget);
  });

  testWidgets('V2 exposes four shell destinations and intelligence', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    for (final label in ['今日', '探索', '路线', '我的']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(find.bySemanticsLabel('栖光：问问题或抽取灵感'), findsOneWidget);
    expect(find.byKey(const Key('v2-bottom-navigation')), findsOneWidget);
    expect(find.byKey(const Key('v2-object-navigation-rail')), findsOneWidget);
    expect(
      find.byKey(const Key('v2-intelligence-navigation-action')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('v2-intelligence-navigation-action')),
        matching: find.text('栖光'),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('v2-moving-selection-lens')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('V2 uses an expanded side rail on wide windows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      LumaNestApp(
        initialContext: ContextFixtures.lakeSunset(observedAt: DateTime.now()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('v2-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('v2-object-navigation-rail')), findsOneWidget);
    expect(find.bySemanticsLabel('今日'), findsOneWidget);
    expect(find.bySemanticsLabel('栖光：问问题或抽取灵感'), findsOneWidget);
  });
}
