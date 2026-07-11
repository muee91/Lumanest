import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/presentation/environment_diagnostics.dart';
import 'package:luma_nest/src/features/profile/presentation/profile_page.dart';

void main() {
  testWidgets(
    'exposes switches for dynamic background, reduce motion and reduce flashing',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentDiagnosticStatusProvider.overrideWithValue(
              EnvironmentDiagnosticStatus.operational,
            ),
          ],
          child: const MaterialApp(home: ProfilePage()),
        ),
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
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
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
        ProviderScope(
          overrides: [
            environmentDiagnosticStatusProvider.overrideWithValue(
              EnvironmentDiagnosticStatus.operational,
            ),
          ],
          child: const MaterialApp(home: ProfilePage()),
        ),
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

  testWidgets('shows no environment diagnostic when fully operational', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('配置'), findsNothing);
    expect(find.textContaining('权限'), findsNothing);
    expect(find.textContaining('缓存'), findsNothing);
    // Switches are still present — the page rendered without diagnostics.
    expect(find.text('动态背景'), findsOneWidget);
  });

  testWidgets('shows QWeather config missing diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.qweatherConfigMissing,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('天气'), findsOneWidget);
  });

  testWidgets('shows AMap config missing diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.amapConfigMissing,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('地图'), findsOneWidget);
  });

  testWidgets('shows location permission denied diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.locationPermissionDenied,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('定位权限'), findsOneWidget);
  });

  testWidgets('shows stale cache diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.staleCache,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('缓存'), findsOneWidget);
  });

  testWidgets(
    'never renders sensitive key or host values in the profile page',
    (tester) async {
      const sensitiveTokens = <String>[
        'AMAP_ANDROID_KEY',
        'QWEATHER_API_KEY',
        'QWEATHER_API_HOST',
        'amapAndroidKey',
        'qweatherApiKey',
        'qweatherApiHost',
      ];

      for (final status in EnvironmentDiagnosticStatus.values) {
        if (status == EnvironmentDiagnosticStatus.operational) continue;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              environmentDiagnosticStatusProvider.overrideWithValue(status),
            ],
            child: const MaterialApp(home: ProfilePage()),
          ),
        );

        for (final token in sensitiveTokens) {
          expect(
            find.text(token),
            findsNothing,
            reason: '$token must not appear for status $status',
          );
          expect(
            find.textContaining(token),
            findsNothing,
            reason: '$token must not be a substring for status $status',
          );
        }
      }
    },
  );
}
