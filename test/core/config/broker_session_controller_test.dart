import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/broker_session_controller.dart';
import 'package:luma_nest/src/core/config/client_session_bootstrap.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';

class _FakeFetch {
  _FakeFetch([this.results = const []]);

  final List<BrokerSessionCredentials?> results;
  final List<EnvironmentConfig> requests = [];
  final Completer<void> gate = Completer<void>();
  bool gated = false;

  Future<BrokerSessionCredentials?> call(EnvironmentConfig config) async {
    requests.add(config);
    if (gated) await gate.future;
    final index = requests.length - 1;
    return index < results.length ? results[index] : null;
  }
}

BrokerSessionCredentials _credentials(
  String token,
  DateTime? expiresAt,
) => BrokerSessionCredentials(accessToken: token, expiresAt: expiresAt);

void main() {
  test('renews before the token expires and propagates the new config', () async {
    final start = DateTime.utc(2026, 11, 1);
    var now = start;
    final fetch = _FakeFetch([
      _credentials('renewed-token-0123456789abcdef0123456789',
          DateTime.utc(2026, 11, 2, 12)),
    ]);
    final updated = <EnvironmentConfig>[];
    final controller = BrokerSessionController(
      initialConfig: EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
        lumaNestServiceToken: 'initial-token-0123456789abcdef0123456',
      ),
      initialCredentials: _credentials(
        'initial-token-0123456789abcdef0123456',
        DateTime.utc(2026, 11, 2),
      ),
      fetch: fetch.call,
      now: () => now,
      onConfigChanged: updated.add,
    )..start();

    // Half an hour before expiry the margin is exhausted.
    now = DateTime.utc(2026, 11, 1, 23, 35);
    await Future<void>.delayed(Duration.zero);
    controller.checkForRenewal();
    await Future<void>.delayed(Duration.zero);

    expect(fetch.requests.length, 1,
        reason: 'the launch check found a fresh token, so only the '
            'expiry-margin tick renews');
    expect(updated.last.lumaNestServiceToken,
        'renewed-token-0123456789abcdef0123456789');
    controller.dispose();
  });

  test('does not renew while the token is fresh', () async {
    final start = DateTime.utc(2026, 11, 1);
    var now = start;
    final fetch = _FakeFetch();
    final controller = BrokerSessionController(
      initialConfig: EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
        lumaNestServiceToken: 'initial-token-0123456789abcdef0123456',
      ),
      initialCredentials: _credentials(
        'initial-token-0123456789abcdef0123456',
        DateTime.utc(2026, 11, 2),
      ),
      fetch: fetch.call,
      now: () => now,
      onConfigChanged: (_) {},
    )..start();
    // start() performs one check; the token is fresh so no fetch happens.
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests, isEmpty);

    now = DateTime.utc(2026, 11, 1, 6);
    controller.checkForRenewal();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests, isEmpty,
        reason: 'six hours before expiry is far outside the 30-minute margin');
    controller.dispose();
  });

  test('concurrent renewal attempts stay single-flight', () async {
    final start = DateTime.utc(2026, 11, 1);
    DateTime now() => start;
    final fetch = _FakeFetch()..gated = true;
    final controller = BrokerSessionController(
      initialConfig: EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
      ),
      fetch: fetch.call,
      now: now,
      onConfigChanged: (_) {},
    )..start();

    controller.checkForRenewal();
    controller.checkForRenewal();
    await Future<void>.delayed(Duration.zero);

    expect(fetch.requests.length, 1,
        reason: 'the in-flight renewal absorbs further attempts');
    controller.dispose();
  });

  test('a failed renewal retries only after the minimum interval', () async {
    final start = DateTime.utc(2026, 11, 1);
    var now = start;
    final fetch = _FakeFetch([null, null]);
    final controller = BrokerSessionController(
      initialConfig: EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
      ),
      fetch: fetch.call,
      now: () => now,
      minimumRetryInterval: const Duration(minutes: 1),
      onConfigChanged: (_) {},
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests.length, 1);

    now = start.add(const Duration(seconds: 30));
    controller.checkForRenewal();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests.length, 1,
        reason: 'still inside the retry interval');

    now = start.add(const Duration(seconds: 61));
    controller.checkForRenewal();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests.length, 2, reason: 'the retry interval elapsed');
    controller.dispose();
  });

  test('resume checks use a wider margin than periodic checks', () async {
    final start = DateTime.utc(2026, 11, 1);
    var now = start;
    final fetch = _FakeFetch([
      _credentials('resume-token-0123456789abcdef01234567', null),
    ]);
    final controller = BrokerSessionController(
      initialConfig: EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
        lumaNestServiceToken: 'initial-token-0123456789abcdef0123456',
      ),
      initialCredentials: _credentials(
        'initial-token-0123456789abcdef0123456',
        DateTime.utc(2026, 11, 1, 21),
      ),
      fetch: fetch.call,
      now: () => now,
      onConfigChanged: (_) {},
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests, isEmpty,
        reason: 'the periodic margin is 30 minutes; three hours remain');

    // A resume two hours before expiry falls inside the wider resume margin
    // because the periodic timer does not run while suspended.
    now = DateTime.utc(2026, 11, 1, 19, 30);
    controller.checkForRenewalOnResume();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests.length, 1);
    controller.dispose();
  });

  test('a successful renewal without expiry assumes a conservative lifetime',
      () async {
    final start = DateTime.utc(2026, 11, 1);
    var now = start;
    final fetch = _FakeFetch([
      _credentials('opaque-token-0123456789abcdef012345678', null),
    ]);
    final controller = BrokerSessionController(
      initialConfig: EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
      ),
      fetch: fetch.call,
      now: () => now,
      onConfigChanged: (_) {},
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests.length, 1);

    // Not even half a day has passed: the assumed 23h lifetime keeps the
    // controller from hammering the issuance quota.
    now = start.add(const Duration(hours: 10));
    controller.checkForRenewal();
    await Future<void>.delayed(Duration.zero);
    expect(fetch.requests.length, 1);
    controller.dispose();
  });
}
