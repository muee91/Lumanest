import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_sky_window_repository.dart';

import '../../core/environment/sky_window_forecast_test.dart' as fixture;

class FakeTransport implements SiteEnvironmentTransport {
  FakeTransport(this.body);

  final Map<String, Object?> body;
  Uri? requestedUri;
  Map<String, String>? requestedHeaders;

  @override
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    requestedUri = uri;
    requestedHeaders = headers;
    return body;
  }
}

void main() {
  test('repository sends bounded UTC request and verifies response binding', () async {
    final transport = FakeTransport(fixture.fixture());
    final repository = DataBrokerSkyWindowRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'secret',
      transport: transport,
    );
    final forecast = await repository.fetch(
      const GeoPoint(latitude: 30, longitude: 100),
      startAt: DateTime.parse('2026-07-23T15:00:00Z'),
      hours: 6,
    );
    expect(forecast.bestWindow?.id, 'sky_window_1');
    expect(transport.requestedUri?.path, '/v1/environment/sky-windows');
    expect(transport.requestedUri?.queryParameters['start'],
        '2026-07-23T15:00:00.000Z');
    expect(transport.requestedUri?.queryParameters['hours'], '6');
    expect(transport.requestedHeaders?['Authorization'], 'Bearer secret');
  });

  test('repository rejects mismatched response coordinates', () async {
    final body = fixture.fixture();
    body['requestedCoordinate'] = {
      'latitude': 31.0,
      'longitude': 100.0,
      'system': 'wgs84',
    };
    final repository = DataBrokerSkyWindowRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'secret',
      transport: FakeTransport(body),
    );
    expect(
      () => repository.fetch(
        const GeoPoint(latitude: 30, longitude: 100),
        startAt: DateTime.parse('2026-07-23T15:00:00Z'),
      ),
      throwsFormatException,
    );
  });
}
