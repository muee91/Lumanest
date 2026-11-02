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

  test('beforeSend actually strips location, request and user context', () async {
    // Asserting the callback merely exists let a broken scrubber pass: delete
    // any field-stripping line and the test still went green while user
    // coordinates and questions reached Sentry.
    final options = SentryFlutterOptions();
    configureSentryOptions(options, 'https://public@example.ingest.sentry.io/123');
    final scrub = options.beforeSend!;

    final event = SentryEvent(
      timestamp: DateTime.utc(2026, 8, 3, 8),
      platform: 'dart',
      level: SentryLevel.error,
      environment: 'production',
      release: '1.0.0',
      message: SentryMessage('context refresh failed'),
      request: SentryRequest(
        url: 'https://broker.example/v1/context/snapshot?latitude=30.25',
        data: {'latitude': 30.25, 'longitude': 120.15, 'question': '今晚能拍吗'},
        headers: {'Authorization': 'Bearer static-token'},
      ),
      user: SentryUser(
        id: 'device-1',
        ipAddress: '203.0.113.9',
        email: 'someone@example.com',
      ),
      contexts: Contexts()..['device'] = SentryDevice(name: 'Pixel 8'),
      breadcrumbs: [
        Breadcrumb(
          message: 'opened /v1/context/snapshot',
          data: {'latitude': 30.25},
        ),
      ],
      tags: {'snapshotId': 'ctx_0123456789abcdef01234567'},
      // ignore: deprecated_member_use
      extra: {'coordinate': '30.25,120.15'},
    );

    final scrubbed = await scrub(event, Hint());

    expect(scrubbed, isNotNull);
    expect(scrubbed!.request, isNull, reason: 'request body carries coordinates');
    expect(scrubbed.user, isNull, reason: 'user identity must never ship');
    // `Contexts` always carries a map of named slots, so the field itself is
    // never null; what ships is `toJson()`, which omits empty slots.
    expect(
      scrubbed.contexts.toJson(),
      isEmpty,
      reason: 'device context is identifying',
    );
    expect(scrubbed.breadcrumbs, isNull, reason: 'breadcrumbs leak navigation');
    // ignore: deprecated_member_use
    expect(scrubbed.extra, isNull, reason: 'extra carries the raw coordinate');
    expect(scrubbed.tags, isNull, reason: 'tags carried the snapshot id');
    // Diagnostics that make a crash actionable are preserved.
    expect(scrubbed.message?.formatted, 'context refresh failed');
    expect(scrubbed.level, SentryLevel.error);
    expect(scrubbed.release, '1.0.0');
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
