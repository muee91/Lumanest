import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';

void main() {
  testWidgets('location onboarding offers a manual place fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: V2TodayPage())),
    );
    await tester.pump();

    expect(find.text('允许位置并继续'), findsOneWidget);
    expect(find.text('先选择一个地点'), findsOneWidget);

    await tester.tap(find.text('先选择一个地点'));
    await tester.pumpAndSettle();

    expect(find.text('手动选择地点'), findsOneWidget);
    expect(find.text('用于天气和光线判断；不会伪装成你的实时位置。'), findsOneWidget);
  });
}
