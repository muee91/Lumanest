import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';

void main() {
  testWidgets('five destinations navigate while keeping the shell visible', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.text('从当前位置开始'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('探索'));
    await tester.pump();
    expect(find.text('地图尚未配置'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('路线'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('去探索选目的地'), findsOneWidget);

    await tester.tap(find.text('灵感'));
    await tester.pump();
    expect(find.text('灵感瓶'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();
    expect(find.text('动态背景'), findsOneWidget);
  });
}
