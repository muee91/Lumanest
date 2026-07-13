import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/monitoring/crash_monitoring.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('missing DSN starts the app without initializing monitoring', () async {
    var calls = 0;

    await runLumaNestWithCrashMonitoring(
      config: EnvironmentConfig(),
      appRunner: () => calls += 1,
    );

    expect(calls, 1);
  });

  test('Sentry options disable user and visual context collection', () {
    final options = SentryFlutterOptions();

    configureSentryOptions(
      options,
      'https://public@example.ingest.sentry.io/123',
    );

    expect(options.sendDefaultPii, isFalse);
    expect(options.attachScreenshot, isFalse);
    expect(options.enableUserInteractionBreadcrumbs, isFalse);
    expect(options.enableUserInteractionTracing, isFalse);
    expect(options.enableAutoNativeBreadcrumbs, isFalse);
    expect(options.enableAutoPerformanceTracing, isFalse);
    expect(options.enableAutoSessionTracking, isFalse);
    expect(options.tracesSampleRate, isNull);
    expect(options.maxBreadcrumbs, 0);
    expect(options.maxCacheItems, 10);
    expect(options.beforeSend, isNotNull);
  });

  test('monitoring initialization failure still starts the app once', () async {
    var calls = 0;

    await runLumaNestWithCrashMonitoring(
      config: EnvironmentConfig(
        sentryDsn: 'https://public@example.ingest.sentry.io/123',
      ),
      appRunner: () => calls += 1,
      initializer: (_, _) => Future<void>.error(StateError('unavailable')),
    );

    expect(calls, 1);
  });
}
