import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _installationIdKey = 'lumanest.installation_id';

/// Obtains a short-lived App-scoped Broker token without embedding the shared
/// server bearer in release builds. The installation identifier is only a
/// quota/revocation handle, not a credential; the access token stays in memory
/// for the current process and is renewed on the next launch.
Future<EnvironmentConfig> bootstrapBrokerSession(
  EnvironmentConfig config, {
  Dio? dio,
  SharedPreferencesAsync? preferences,
}) async {
  if (!config.isBrokerBaseConfigured ||
      config.lumaNestServiceToken.isNotEmpty) {
    return config;
  }

  final store = preferences ?? SharedPreferencesAsync();
  final installationId = await _installationId(store);
  final nonce = _randomToken(24);
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
      data: {'installationId': installationId, 'nonce': nonce},
    );
    final token = response.data?['accessToken'];
    if (token is! String || token.length < 40) return config;
    return config.withServiceToken(token);
  } on DioException {
    return config;
  } catch (_) {
    return config;
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

String _randomToken(int bytes) {
  final random = Random.secure();
  final value = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64Url.encode(value).replaceAll('=', '');
}
