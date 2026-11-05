import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/client_session_bootstrap.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bootstrap is the only part of the session credential path that touches
/// a socket; these cases run the real [Dio] pipeline over a stub adapter so
/// timeouts, body shapes and the persisted installation identity are exercised
/// the way they fail in the wild.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;
  RequestOptions? lastRequest;
  Object? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    lastRequest = options;
    lastBody = options.data;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeDeviceSecretStore implements DeviceSecretStore {
  final values = <String, String>{};
  bool failRead = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('secure storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

EnvironmentConfig _sessionConfig() =>
    EnvironmentConfig(dataBrokerBaseUrl: 'https://broker.example');

Dio _dio(_StubAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 200),
      receiveTimeout: const Duration(milliseconds: 200),
      sendTimeout: const Duration(milliseconds: 200),
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDeviceSecretStore secrets;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets = _FakeDeviceSecretStore();
  });

  test('issues a session token for a session-eligible config', () async {
    final adapter = _StubAdapter(
      (_) async => ResponseBody.fromString(
        '{"accessToken":"issued-session-token-0123456789abcdefghij",'
        '"expiresAt":"2026-11-02T00:00:00Z"}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final dio = _dio(adapter);

    final bootstrap = await bootstrapBrokerSession(
      _sessionConfig(),
      dio: dio,
      secureStorage: secrets,
    );

    expect(adapter.lastRequest?.method, 'POST');
    expect(
      adapter.lastRequest?.uri.toString(),
      'https://broker.example/v1/session',
    );
    final body = adapter.lastBody as Map;
    // The installation identifier remains public metadata; the owner secret
    // is the private device binding used to mint a session.
    expect(body.keys.length, 2);
    expect(body.containsKey('installationId'), true);
    expect((body['installationId'] as String).length, greaterThanOrEqualTo(22));
    expect(body.containsKey('ownerSecret'), true);
    expect(
      RegExp(
        r'^[A-Za-z0-9_-]{43,128}$',
      ).hasMatch(body['ownerSecret'] as String),
      true,
    );

    expect(
      bootstrap.config.lumaNestServiceToken,
      'issued-session-token-0123456789abcdefghij',
    );
    expect(
      bootstrap.credentials?.accessToken,
      'issued-session-token-0123456789abcdefghij',
    );
    expect(bootstrap.credentials?.expiresAt, DateTime.utc(2026, 11, 2));
    dio.close(force: true);
  });

  test('keeps the config untouched when the broker is unreachable', () async {
    final adapter = _StubAdapter(
      (_) async => Future.delayed(
        const Duration(milliseconds: 500),
        () => throw DioException.connectionTimeout(
          requestOptions: RequestOptions(path: '/v1/session'),
          timeout: const Duration(milliseconds: 200),
        ),
      ),
    );
    final dio = _dio(adapter);

    final config = _sessionConfig();
    final bootstrap = await bootstrapBrokerSession(
      config,
      dio: dio,
      secureStorage: secrets,
    );

    expect(identical(bootstrap.config, config), true);
    expect(bootstrap.credentials, isNull);
    dio.close(force: true);
  });

  test('rejects malformed token payloads', () async {
    final adapter = _StubAdapter(
      (_) async => ResponseBody.fromString('{"accessToken":"short"}', 200),
    );
    final dio = _dio(adapter);

    final config = _sessionConfig();
    final bootstrap = await bootstrapBrokerSession(
      config,
      dio: dio,
      secureStorage: secrets,
    );

    expect(bootstrap.config.lumaNestServiceToken, '');
    expect(bootstrap.credentials, isNull);
    dio.close(force: true);
  });

  test(
    'an embedded debug bearer skips the session endpoint entirely',
    () async {
      final adapter = _StubAdapter((_) async => fail('must not be called'));
      final dio = _dio(adapter);

      final config = EnvironmentConfig(
        dataBrokerBaseUrl: 'https://broker.example',
        lumaNestServiceToken: 'embedded-debug-bearer',
      );
      final bootstrap = await bootstrapBrokerSession(
        config,
        dio: dio,
        secureStorage: secrets,
      );

      expect(adapter.lastRequest, isNull);
      expect(bootstrap.credentials, isNull);
      expect(bootstrap.config.lumaNestServiceToken, 'embedded-debug-bearer');
      dio.close(force: true);
    },
  );

  test('rotates a corrupted installation id before requesting', () async {
    SharedPreferences.setMockInitialValues({
      'lumanest.installation_id': 'corrupted id with spaces!!',
    });
    final adapter = _StubAdapter(
      (_) async => ResponseBody.fromString(
        '{"accessToken":"issued-session-token-0123456789abcdefghij"}',
        200,
      ),
    );
    final dio = _dio(adapter);

    await bootstrapBrokerSession(
      _sessionConfig(),
      dio: dio,
      secureStorage: secrets,
    );

    final body = adapter.lastBody as Map;
    final installationId = body['installationId'] as String;
    expect(
      RegExp(r'^[A-Za-z0-9_-]{22,80}$').hasMatch(installationId),
      true,
      reason: 'the corrupted id must be replaced with a fresh valid one',
    );
    expect(installationId.contains(' '), false);

    final stored = await SharedPreferencesAsync().getString(
      'lumanest.installation_id',
    );
    expect(
      stored,
      installationId,
      reason: 'the rotated id must persist for the next launch',
    );
    dio.close(force: true);
  });

  test('reuses the persisted owner secret across session renewals', () async {
    final bodies = <Map<Object?, Object?>>[];
    final adapter = _StubAdapter((options) async {
      bodies.add(Map<Object?, Object?>.from(options.data as Map));
      return ResponseBody.fromString(
        '{"accessToken":"issued-session-token-0123456789abcdefghij"}',
        200,
      );
    });
    final dio = _dio(adapter);

    await bootstrapBrokerSession(
      _sessionConfig(),
      dio: dio,
      secureStorage: secrets,
    );
    await bootstrapBrokerSession(
      _sessionConfig(),
      dio: dio,
      secureStorage: secrets,
    );

    expect(bodies, hasLength(2));
    expect(bodies[0]['ownerSecret'], bodies[1]['ownerSecret']);
    expect(bodies[0]['installationId'], bodies[1]['installationId']);
    dio.close(force: true);
  });

  test(
    'migrates the legacy preferences secret without rotating identity',
    () async {
      const legacy =
          'owner-secret-legacy-abcdefghijklmnopqrstuvwxyz-0123456789';
      final preferences = SharedPreferencesAsync();
      await preferences.setString('lumanest.device_owner_secret', legacy);
      final adapter = _StubAdapter(
        (_) async => ResponseBody.fromString(
          '{"accessToken":"issued-session-token-0123456789abcdefghij"}',
          200,
        ),
      );
      final dio = _dio(adapter);

      await bootstrapBrokerSession(
        _sessionConfig(),
        dio: dio,
        preferences: preferences,
        secureStorage: secrets,
      );

      expect(secrets.values['lumanest.device_owner_secret'], legacy);
      expect(
        await preferences.getString('lumanest.device_owner_secret'),
        isNull,
      );
      dio.close(force: true);
    },
  );

  test('secure-store read failure does not issue a new identity', () async {
    secrets.failRead = true;
    final adapter = _StubAdapter((_) async => fail('must not call the broker'));
    final dio = _dio(adapter);
    final result = await bootstrapBrokerSession(
      _sessionConfig(),
      dio: dio,
      secureStorage: secrets,
    );
    expect(result.credentials, isNull);
    expect(secrets.values, isEmpty);
    expect(adapter.lastRequest, isNull);
    dio.close(force: true);
  });
}
