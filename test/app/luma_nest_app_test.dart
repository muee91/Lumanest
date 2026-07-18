import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';

void main() {
  testWidgets('shows privacy-first entry and five destinations', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());

    expect(find.text('从此刻的位置开始'), findsOneWidget);
    expect(find.bySemanticsLabel('今日'), findsOneWidget);
    expect(find.bySemanticsLabel('探索'), findsOneWidget);
    expect(find.bySemanticsLabel('路线'), findsOneWidget);
    expect(find.bySemanticsLabel('灵感'), findsOneWidget);
    expect(find.bySemanticsLabel('我的'), findsOneWidget);
  });

  testWidgets('accepts an injected context snapshot', (tester) async {
    await tester.pumpWidget(
      LumaNestApp(
        initialContext: ContextFixtures.lakeSunset(observedAt: DateTime.now()),
      ),
    );

    expect(find.text('栖光此刻看到'), findsOneWidget);
    expect(find.text('这个窗口值得你提前到场。'), findsOneWidget);
    expect(find.textContaining('82%'), findsNothing);
    expect(find.textContaining('置信度'), findsNothing);
  });

  testWidgets('quiet Today keeps one judgment line and distinct actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      LumaNestApp(initialContext: ContextFixtures.quietCity()),
    );
    await tester.pump();

    final judgement = tester.widget<Text>(
      find.byKey(const Key('v2-today-judgement')),
    );
    expect(judgement.maxLines, 1);
    expect(judgement.softWrap, isFalse);
    expect(find.text('探索附近'), findsOneWidget);
    expect(find.text('选择参考地点'), findsOneWidget);
    expect(find.text('换个方向看看'), findsNothing);
  });
}
