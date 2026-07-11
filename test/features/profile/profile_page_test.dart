import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiguang/src/features/profile/presentation/profile_page.dart';

void main() {
  testWidgets(
    'exposes switches for dynamic background, reduce motion and reduce flashing',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProfilePage())),
      );

      expect(find.text('动态背景'), findsOneWidget);
      expect(find.text('减少动效'), findsOneWidget);
      expect(find.text('减少闪烁'), findsOneWidget);
    },
  );

  testWidgets('tapping the dynamic background switch flips the value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfilePage())),
    );

    final dynamicSwitch = find.ancestor(
      of: find.text('动态背景'),
      matching: find.byType(SwitchListTile),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is SwitchListTile && widget.value == true,
      ),
      findsOneWidget,
      reason: 'ambient background defaults to enabled',
    );

    await tester.tap(dynamicSwitch);
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            widget.title is Text &&
            (widget.title as Text).data == '动态背景' &&
            widget.value == false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'does not render empty groups for unavailable collections, routes or devices',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ProfilePage())),
      );

      expect(
        find.text('我的收藏'),
        findsNothing,
        reason: 'collections group must not render when empty',
      );
      expect(
        find.text('已保存路线'),
        findsNothing,
        reason: 'routes group must not render when empty',
      );
      expect(
        find.text('已连接设备'),
        findsNothing,
        reason: 'devices group must not render when empty',
      );
      expect(
        find.text('暂无收藏'),
        findsNothing,
        reason: 'no empty-state placeholders for collections',
      );
      expect(
        find.text('暂无路线'),
        findsNothing,
        reason: 'no empty-state placeholders for routes',
      );
      expect(
        find.text('暂无设备'),
        findsNothing,
        reason: 'no empty-state placeholders for devices',
      );
    },
  );
}
