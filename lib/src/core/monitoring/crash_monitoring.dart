import 'package:flutter/foundation.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

typedef AppRunner = void Function();
typedef CrashMonitoringInitializer =
    Future<void> Function(String dsn, AppRunner appRunner);

Future<void> runLumaNestWithCrashMonitoring({
  required EnvironmentConfig config,
  required AppRunner appRunner,
  CrashMonitoringInitializer initializer = _initializeSentry,
}) async {
  if (!config.isSentryConfigured) {
    appRunner();
    return;
  }

  var appStarted = false;
  void startAppOnce() {
    if (appStarted) return;
    appStarted = true;
    appRunner();
  }

  try {
    await initializer(config.sentryDsn, startAppOnce);
  } catch (_) {
    startAppOnce();
  }
}

Future<void> _initializeSentry(String dsn, AppRunner appRunner) {
  return SentryFlutter.init(
    (options) => configureSentryOptions(options, dsn),
    appRunner: appRunner,
  );
}

void configureSentryOptions(SentryFlutterOptions options, String dsn) {
  options
    ..dsn = dsn
    ..environment = kReleaseMode ? 'production' : 'debug'
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..enableUserInteractionBreadcrumbs = false
    ..enableUserInteractionTracing = false
    ..enableAutoNativeBreadcrumbs = false
    ..enableAutoPerformanceTracing = false
    ..enableAutoSessionTracking = false
    ..tracesSampleRate = null
    ..maxBreadcrumbs = 0
    ..maxCacheItems = 10
    ..beforeSend = _stripApplicationContext;
}

SentryEvent _stripApplicationContext(SentryEvent event, Hint hint) {
  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    platform: event.platform,
    logger: event.logger,
    release: event.release,
    dist: event.dist,
    environment: event.environment,
    throwable: event.throwableMechanism,
    level: event.level,
    exceptions: event.exceptions,
    threads: event.threads,
    sdk: event.sdk,
    debugMeta: event.debugMeta,
  );
}
