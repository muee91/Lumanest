import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

void main() {
  testWidgets('malformed whitelisted action reports expiry instead of no-op', (
    tester,
  ) async {
    const item = ManifestItem(
      id: 'astronomy-without-url',
      title: '天象目录',
      action: ManifestAction.openAuthority,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => handleManifestAction(context, item),
              child: const Text('执行'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('执行'));
    await tester.pump();

    expect(find.text('这个动作已失效，请刷新情境后重试'), findsOneWidget);
  });

  testWidgets('safety panel exposes event authority and validity metadata', (
    tester,
  ) async {
    final item = ManifestItem(
      id: 'official-warning',
      title: '官方安全预警',
      action: ManifestAction.openSafety,
      source: ContextEventSource.official,
      observedAt: DateTime.utc(2026, 7, 16, 2),
      expiresAt: DateTime.utc(2026, 7, 16, 3),
      geoScope: ContextGeoScope.regional,
      safetyLevel: ContextSafetyLevel.critical,
      confidence: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => handleManifestAction(context, item),
              child: const Text('查看安全提醒'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看安全提醒'));
    await tester.pumpAndSettle();

    expect(find.textContaining('官方来源'), findsOneWidget);
    expect(find.textContaining('严重'), findsOneWidget);
    expect(find.textContaining('附近区域'), findsOneWidget);
    expect(find.textContaining('更新'), findsOneWidget);
    expect(find.textContaining('前有效'), findsOneWidget);
    expect(find.text('当前置信度 100%'), findsOneWidget);
  });

  testWidgets('safety panel presents deterministic guidance separately', (
    tester,
  ) async {
    const item = ManifestItem(
      id: 'official-warning',
      title: '雷电红色预警',
      action: ManifestAction.openSafety,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => handleManifestAction(
                context,
                item,
                detailOverride: '未来两小时有强雷电活动。',
                guidance: const ['远离制高点和水边。'],
              ),
              child: const Text('查看预警'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看预警'));
    await tester.pumpAndSettle();

    expect(find.text('未来两小时有强雷电活动。'), findsOneWidget);
    expect(find.text('现在做什么'), findsOneWidget);
    expect(find.text('远离制高点和水边。'), findsOneWidget);
  });
}
