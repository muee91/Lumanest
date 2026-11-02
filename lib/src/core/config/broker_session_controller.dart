import 'dart:async';

import 'package:luma_nest/src/core/config/client_session_bootstrap.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';

typedef BrokerSessionFetch =
    Future<BrokerSessionCredentials?> Function(EnvironmentConfig config);

/// Keeps the short-lived broker session token fresh for long-lived processes.
///
/// The session token expires after 24 hours; without renewal every broker
/// call would fail with 401 until the user restarts the app - a real break
/// for the "keep the phone in a pocket while hiking" scenario. The controller
/// renews proactively before expiry (and with a wider margin when the app
/// resumes, because timers do not run while suspended) and propagates the new
/// configuration through [onConfigChanged] so every provider watching the
/// environment config rebuilds with the fresh token.
class BrokerSessionController {
  BrokerSessionController({
    required EnvironmentConfig initialConfig,
    required this.onConfigChanged,
    this.fetch = _defaultFetch,
    this.initialCredentials,
    DateTime Function()? now,
    this.checkInterval = const Duration(minutes: 5),
    this.renewMargin = const Duration(minutes: 30),
    this.resumeMargin = const Duration(hours: 2),
    this.minimumRetryInterval = const Duration(minutes: 1),
    this.assumedTokenLifetime = const Duration(hours: 23),
  }) : _config = initialConfig,
       _now = now ?? DateTime.now,
       _expiresAt = initialCredentials?.expiresAt;

  static Future<BrokerSessionCredentials?> _defaultFetch(
    EnvironmentConfig config,
  ) => fetchBrokerSessionCredentials(config);

  final void Function(EnvironmentConfig next) onConfigChanged;
  final BrokerSessionFetch fetch;

  /// Credentials from the launch bootstrap, used to schedule the first
  /// renewal; null when launch could not obtain a token yet.
  final BrokerSessionCredentials? initialCredentials;

  final Duration checkInterval;

  /// Renew this long before the token expires while the app is in the
  /// foreground and timers run.
  final Duration renewMargin;

  /// Renew this long before expiry when the app resumes: the periodic check
  /// may have missed its slot while the process was suspended.
  final Duration resumeMargin;

  /// Failed attempts wait at least this long before retrying, so an
  /// unreachable broker does not burn the per-installation issuance quota.
  final Duration minimumRetryInterval;

  /// When the server omits a parseable expiry, assume the token lasts this
  /// long instead of renewing on every check.
  final Duration assumedTokenLifetime;

  final DateTime Function() _now;
  EnvironmentConfig _config;
  DateTime? _expiresAt;
  DateTime _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _renewing = false;
  Timer? _timer;
  bool _started = false;

  bool get isRunning => _started;

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(checkInterval, (_) => checkForRenewal());
    // The launch bootstrap may have failed (offline cold start); try again
    // once the first frame is up, respecting the retry interval.
    checkForRenewal();
  }

  void dispose() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Periodic tick: renew only when the token is missing or close to expiry.
  void checkForRenewal() {
    if (!_started) return;
    final expiry = _effectiveExpiry();
    final needsRenewal = _config.lumaNestServiceToken.isEmpty ||
        expiry == null ||
        _now().isAfter(expiry.subtract(renewMargin));
    if (needsRenewal) {
      unawaited(_renewOnce());
    }
  }

  /// App resume: same rule with a wider margin, because the periodic timer
  /// does not fire while the process is suspended.
  void checkForRenewalOnResume() {
    if (!_started) return;
    final expiry = _effectiveExpiry();
    final needsRenewal = _config.lumaNestServiceToken.isEmpty ||
        expiry == null ||
        _now().isAfter(expiry.subtract(resumeMargin));
    if (needsRenewal) {
      unawaited(_renewOnce());
    }
  }

  DateTime? _effectiveExpiry() => _expiresAt;

  Future<void> _renewOnce() async {
    if (_renewing) return;
    final now = _now();
    if (now.difference(_lastAttemptAt) < minimumRetryInterval) return;
    _renewing = true;
    _lastAttemptAt = now;
    try {
      final credentials = await fetch(_config);
      if (credentials != null) {
        _config = _config.withServiceToken(credentials.accessToken);
        _expiresAt =
            credentials.expiresAt ??
            _now().add(assumedTokenLifetime);
        onConfigChanged(_config);
      }
      // A null result keeps the current token (if any) and the old schedule;
      // the next tick retries after the minimum interval.
    } finally {
      _renewing = false;
    }
  }
}
