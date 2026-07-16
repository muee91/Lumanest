import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';
import 'package:luma_nest/src/app/router.dart';

void main() {
  test('shooting-window route keeps only a validated opportunity ID', () {
    final location = shootingWindowLocation('photo-sunset_1');

    expect(location, '/shooting-window?opportunity=photo-sunset_1');
    expect(
      shootingWindowOpportunityIdFrom(Uri.parse(location)),
      'photo-sunset_1',
    );
    expect(
      shootingWindowOpportunityIdFrom(
        Uri.parse('/shooting-window?opportunity=unknown'),
      ),
      isNull,
    );
    expect(
      shootingWindowOpportunityIdFrom(
        Uri.parse('/shooting-window?opportunity=photo-valid&extra=1'),
      ),
      isNull,
    );
  });

  testWidgets('five destinations navigate while keeping the shell visible', (
    tester,
  ) async {
    await tester.pumpWidget(const LumaNestApp());
    await tester.pump();

    expect(find.text('从当前位置开始'), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-navigation')), findsOneWidget);

    await tester.tap(find.text('探索'));
    await tester.pump();
    expect(find.text('地图尚未配置'), findsOneWidget);
    expect(find.byKey(const Key('app-bottom-navigation')), findsOneWidget);

    await tester.tap(find.text('路线'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('去探索选目的地'), findsOneWidget);

    await tester.tap(find.text('灵感'));
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('灵感'), findsWidgets);

    await tester.tap(find.text('我的'));
    await tester.pump();
    expect(find.text('显示与动效'), findsOneWidget);
    expect(find.text('创作偏好'), findsOneWidget);
    expect(find.text('AI 文案'), findsOneWidget);
  });
}
