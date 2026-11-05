import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installationIdKey = 'lumanest.installation_id';
const _ownerSecretKey = 'lumanest.device_owner_secret';

/// The short-lived App-scoped credentials returned by `POST /v1/session`.
class BrokerSessionCredentials {
  const BrokerSessionCredentials({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;

  /// When the broker will stop accepting [accessToken]; null when the server
  /// did not answer with a parseable timestamp.
  final DateTime? expiresAt;
}

/// The result of the one-shot startup bootstrap: the configuration to run the
/// app with, plus the session credentials when a token was actually issued.
class BrokerSessionBootstrap {
  const BrokerSessionBootstrap({required this.config, this.credentials});

  final EnvironmentConfig config;

  /// Null when no session was attempted (embedded debug token, unconfigured
  /// base URL) or when the broker was unreachable at launch.
  final BrokerSessionCredentials? credentials;
}

/// The device-bound secret must survive app restarts without being kept in a
/// general preferences database. Tests inject an in-memory implementation;
/// production uses Android Keystore / iOS Keychain through this boundary.
abstract interface class DeviceSecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterDeviceSecretStore implements DeviceSecretStore {
  FlutterDeviceSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Obtains a short-lived App-scoped Broker token without embedding the shared
/// server bearer in release builds. The installation identifier is the
/// server-side quota and revocation handle, not a credential; the access token
/// stays in memory for the current process and is renewed before it expires.
Future<BrokerSessionBootstrap> bootstrapBrokerSession(
  EnvironmentConfig config, {
  Dio? dio,
  SharedPreferencesAsync? preferences,
  DeviceSecretStore? secureStorage,
}) async {
  if (!config.isBrokerBaseConfigured ||
      config.lumaNestServiceToken.isNotEmpty) {
    return BrokerSessionBootstrap(config: config);
  }
  final credentials = await fetchBrokerSessionCredentials(
    config,
    dio: dio,
    preferences: preferences,
    secureStorage: secureStorage,
  );
  if (credentials == null) {
    return BrokerSessionBootstrap(config: config);
  }
  return BrokerSessionBootstrap(
    config: config.withServiceToken(credentials.accessToken),
    credentials: credentials,
  );
}

/// One session bootstrap or renewal round trip. Returns null whenever the
/// broker is unreachable or refuses the installation, leaving the caller's
/// current configuration untouched. Callers decide whether an already-present
/// token (embedded or session) should stop the attempt.
Future<BrokerSessionCredentials?> fetchBrokerSessionCredentials(
  EnvironmentConfig config, {
  Dio? dio,
  SharedPreferencesAsync? preferences,
  DeviceSecretStore? secureStorage,
}) async {
  if (!config.isBrokerBaseConfigured) {
    return null;
  }
  final brokerUri = Uri.tryParse(config.dataBrokerBaseUrl);
  if (brokerUri == null ||
      brokerUri.scheme != 'https' ||
      brokerUri.host.isEmpty) {
    return null;
  }

  final store = preferences ?? SharedPreferencesAsync();
  final deviceSecrets = secureStorage ?? FlutterDeviceSecretStore();
  final installationId = await _installationId(store);
  final ownerSecret = await _ownerSecret(store, deviceSecrets);
  if (ownerSecret == null) return null;
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
  try {
    final response = await client.post<Map<String, Object?>>(
      '${config.dataBrokerBaseUrl}/v1/session',
      data: {'installationId': installationId, 'ownerSecret': ownerSecret},
    );
    final token = response.data?['accessToken'];
    if (token is! String || token.length < 40) return null;
    final rawExpiresAt = response.data?['expiresAt'];
    return BrokerSessionCredentials(
      accessToken: token,
      expiresAt: rawExpiresAt is String
          ? DateTime.tryParse(rawExpiresAt)?.toUtc()
          : null,
    );
  } on DioException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (dio == null) client.close(force: true);
  }
}

Future<String> _installationId(SharedPreferencesAsync store) async {
  final existing = await store.getString(_installationIdKey);
  if (existing != null &&
      RegExp(r'^[A-Za-z0-9_-]{22,80}$').hasMatch(existing)) {
    return existing;
  }
  final created = _randomToken(32);
  await store.setString(_installationIdKey, created);
  return created;
}

Future<String?> _ownerSecret(
  SharedPreferencesAsync preferences,
  DeviceSecretStore secureStorage,
) async {
  String? secureValue;
  try {
    secureValue = await secureStorage.read(_ownerSecretKey);
  } on Object {
    // A secure-store read failure must never mint a replacement identity.
    return null;
  }
  if (secureValue != null) {
    return RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(secureValue)
        ? secureValue
        : null;
  }

  // Migrate the old preferences value once, preserving the existing owner
  // rather than silently creating a second cloud identity after an upgrade.
  String? legacy;
  try {
    legacy = await preferences.getString(_ownerSecretKey);
  } on Object {
    return null;
  }
  if (legacy != null && RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(legacy)) {
    try {
      await secureStorage.write(_ownerSecretKey, legacy);
      await preferences.remove(_ownerSecretKey);
      return legacy;
    } on Object {
      return null;
    }
  }

  final created = _randomToken(32);
  try {
    await secureStorage.write(_ownerSecretKey, created);
    return created;
  } on Object {
    return null;
  }
}

String _randomToken(int bytes) {
  final random = Random.secure();
  final value = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64Url.encode(value).replaceAll('=', '');
}
