import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';

/// The transport is the only part of the client that touches a socket, and it
/// was the only part with no test: every repository test replaced it with a
/// fake. These cases run the real [Dio] pipeline over a stub adapter so status
/// codes, timeouts and body shapes are exercised the way they fail in the wild.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;
  RequestOptions? lastRequest;
  Object? lastBody;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls += 1;
    lastRequest = options;
    lastBody = options.data;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 50),
      receiveTimeout: const Duration(milliseconds: 50),
    ));
  });

  tearDown(() => dio.close(force: true));

  DataBrokerContextRepository repositoryWith(_StubAdapter adapter) {
    dio.httpClientAdapter = adapter;
    return DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: DioContextDataTransport(dio),
    );
  }

  Future<void> fetch(DataBrokerContextRepository repository) =>
      repository.fetchSnapshot(
        location: LocationReading(
          point: const GeoPoint(latitude: 30.25, longitude: 120.15),
          recordedAt: DateTime.utc(2026, 7, 14, 2),
          accuracyMeters: 8,
        ),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

  test('posts the canonical body to the snapshot path with the service token',
      () async {
    final adapter = _StubAdapter(
      (_) async => ResponseBody.fromString(
        '{"contractVersion":5}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final repository = repositoryWith(adapter);

    await expectLater(
      fetch(repository),
      throwsA(isA<RemoteContextFailure>()),
    );

    expect(adapter.lastRequest?.method, 'POST');
    expect(
      adapter.lastRequest?.uri.toString(),
      'https://broker.example/v1/context/snapshot',
    );
    expect(
      adapter.lastRequest?.headers['Authorization'],
      'Bearer service-token',
    );
    expect((adapter.lastBody as Map)['contractVersion'], 5);
  });

  test('maps a 429 from the broker to rateLimited, which is not retried',
      () async {
    final adapter = _StubAdapter(
      (_) async => ResponseBody.fromString('{"error":"rate_limited"}', 429),
    );
    final repository = repositoryWith(adapter);

    await expectLater(
      fetch(repository),
      throwsA(
        isA<RemoteContextFailure>().having(
          (failure) => failure.kind,
          'kind',
          RemoteContextFailureKind.rateLimited,
        ),
      ),
    );
    // The name of this test is a contract: a rate limit must surface as a
    // failure to the caller, never as a background retry that would amplify
    // the pressure on the broker.
    expect(adapter.calls, 1);
  });

  test('maps a request timeout to network instead of a response failure',
      () async {
    final repository = repositoryWith(
      _StubAdapter(
        (options) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      ),
    );

    await expectLater(
      fetch(repository),
      throwsA(
        isA<RemoteContextFailure>().having(
          (failure) => failure.kind,
          'kind',
          RemoteContextFailureKind.network,
        ),
      ),
    );
  });

  test('a JSON array body is rejected as a response failure, not a crash',
      () async {
    final repository = repositoryWith(
      _StubAdapter(
        (_) async => ResponseBody.fromString(
          '[]',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    await expectLater(
      fetch(repository),
      throwsA(
        isA<RemoteContextFailure>().having(
          (failure) => failure.kind,
          'kind',
          RemoteContextFailureKind.response,
        ),
      ),
    );
  });

  test('a non-JSON body is rejected as a response failure', () async {
    final repository = repositoryWith(
      _StubAdapter(
        (_) async => ResponseBody.fromString(
          '<html>bad gateway</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      ),
    );

    await expectLater(
      fetch(repository),
      throwsA(
        isA<RemoteContextFailure>().having(
          (failure) => failure.kind,
          'kind',
          RemoteContextFailureKind.response,
        ),
      ),
    );
  });
}
