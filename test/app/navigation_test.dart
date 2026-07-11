import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';

void main() {
  testWidgets('five destinations navigate while keeping the shell visible', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.text('探索附近'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('探索'));
    await tester.pump();
    expect(find.text('查看附近'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('路线'));
    await tester.pump();
    expect(find.text('创建路线'), findsOneWidget);

    await tester.tap(find.text('灵感'));
    await tester.pump();
    expect(find.text('抽一张纸条'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();
    expect(find.text('动态背景'), findsOneWidget);
  });
}
