import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/app/router.dart';

void main() {
  test('session route keeps only a validated stable ID', () {
    final location = shootingSessionLocation('photo-sunset_1');

    expect(location, '/session/photo-sunset_1');
    expect(shootingSessionIdFrom(Uri.parse(location)), 'photo-sunset_1');
    expect(shootingSessionIdFrom(Uri.parse('/session/x')), isNull);
    expect(
      shootingSessionIdFrom(Uri.parse('/opportunity/photo-valid')),
      isNull,
    );
  });

  testWidgets('five destinations navigate while keeping the shell visible', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.text('从此刻的位置开始'), findsOneWidget);
    expect(find.byKey(const Key('v2-bottom-navigation')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('探索'));
    await tester.pump();
    expect(find.text('地图从你所在之处展开'), findsOneWidget);
    expect(find.byKey(const Key('v2-bottom-navigation')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('路线'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('先选一个要抵达的地方'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('灵感'));
    await tester.pump();
    expect(find.text('灵感'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('我的'));
    await tester.pump();
    expect(find.text('栖光如何理解我'), findsOneWidget);
    expect(find.text('风格'), findsOneWidget);
    expect(find.text('留下的'), findsOneWidget);
    expect(find.text('隐私'), findsOneWidget);
  });
}
