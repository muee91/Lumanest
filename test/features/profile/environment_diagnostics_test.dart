import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/presentation/environment_diagnostics.dart';

void main() {
  group('EnvironmentDiagnostics widget', () {
    testWidgets('operational status reserves no space', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Column(
              children: [
                const EnvironmentDiagnostics(
                  status: EnvironmentDiagnosticStatus.operational,
                  actions: EnvironmentDiagnosticsActions(),
                ),
                const Text('content-below'),
              ],
            ),
          ),
        ),
      );

      final diagnosticsSize = tester.getSize(
        find.byType(EnvironmentDiagnostics),
      );
      expect(
        diagnosticsSize.height,
        0,
        reason: 'a healthy system must not reserve any vertical space',
      );

      expect(find.text('content-below'), findsOneWidget);
      expect(find.textContaining('配置'), findsNothing);
      expect(find.textContaining('权限'), findsNothing);
      expect(find.textContaining('缓存'), findsNothing);
    });

    testWidgets('shows concise message for missing AMap config', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentDiagnostics(
            status: EnvironmentDiagnosticStatus.amapConfigMissing,
            actions: const EnvironmentDiagnosticsActions(),
          ),
        ),
      );

      expect(find.textContaining('地图'), findsOneWidget);
    });

    testWidgets('shows concise message for missing QWeather config', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentDiagnostics(
            status: EnvironmentDiagnosticStatus.qweatherConfigMissing,
            actions: const EnvironmentDiagnosticsActions(),
          ),
        ),
      );

      expect(find.textContaining('天气'), findsOneWidget);
    });

    testWidgets('shows concise message for denied location permission', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentDiagnostics(
            status: EnvironmentDiagnosticStatus.locationPermissionDenied,
            actions: const EnvironmentDiagnosticsActions(),
          ),
        ),
      );

      expect(find.textContaining('定位权限'), findsOneWidget);
    });

    testWidgets('shows concise message for stale cache', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentDiagnostics(
            status: EnvironmentDiagnosticStatus.staleCache,
            actions: const EnvironmentDiagnosticsActions(),
          ),
        ),
      );

      expect(find.textContaining('缓存'), findsOneWidget);
    });

    testWidgets(
      'never renders sensitive key or host values in any diagnostic state',
      (tester) async {
        const sensitiveTokens = <String>[
          'AMAP_ANDROID_KEY',
          'QWEATHER_API_KEY',
          'QWEATHER_API_HOST',
          'sk-',
          'amapAndroidKey',
          'qweatherApiKey',
          'qweatherApiHost',
        ];

        for (final status in EnvironmentDiagnosticStatus.values) {
          if (status == EnvironmentDiagnosticStatus.operational) continue;

          await tester.pumpWidget(
            MaterialApp(
              home: EnvironmentDiagnostics(
                status: status,
                actions: const EnvironmentDiagnosticsActions(),
              ),
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

    testWidgets('tapping the retry action invokes onRetry callback', (
      tester,
    ) async {
      var retryCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentDiagnostics(
            status: EnvironmentDiagnosticStatus.staleCache,
            actions: EnvironmentDiagnosticsActions(
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('重试'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });

    testWidgets(
      'tapping the open-settings action invokes onOpenLocationSettings',
      (tester) async {
        var settingsCalled = false;
        await tester.pumpWidget(
          MaterialApp(
            home: EnvironmentDiagnostics(
              status: EnvironmentDiagnosticStatus.locationPermissionDenied,
              actions: EnvironmentDiagnosticsActions(
                onOpenLocationSettings: () => settingsCalled = true,
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开设置'));
        await tester.pump();

        expect(settingsCalled, isTrue);
      },
    );

    testWidgets(
      'tapping the privacy-consent action invokes onOpenPrivacyConsent',
      (tester) async {
        var consentCalled = false;
        await tester.pumpWidget(
          MaterialApp(
            home: EnvironmentDiagnostics(
              status: EnvironmentDiagnosticStatus.amapConfigMissing,
              actions: EnvironmentDiagnosticsActions(
                onOpenPrivacyConsent: () => consentCalled = true,
              ),
            ),
          ),
        );

        await tester.tap(find.text('查看隐私授权'));
        await tester.pump();

        expect(consentCalled, isTrue);
      },
    );

    testWidgets(
      'does not render an action button when the callback is null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: EnvironmentDiagnostics(
              status: EnvironmentDiagnosticStatus.staleCache,
              actions: const EnvironmentDiagnosticsActions(),
            ),
          ),
        );

        expect(find.textContaining('缓存'), findsOneWidget);
        expect(
          find.text('重试'),
          findsNothing,
          reason: 'no retry button should render without a callback',
        );
      },
    );
  });
}
