import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_provider_facts_repository.dart';

void main() {
  test(
    'requests bounded provider facts and validates coordinate binding',
    () async {
      final transport = _FakeTransport(_body());
      final repository = DataBrokerProviderFactsRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'token',
        transport: transport,
      );
      const point = GeoPoint(
        latitude: 30.25,
        longitude: 120.15,
        coordinateSystem: CoordinateSystem.wgs84,
      );

      final result = await repository.fetch(
        point,
        radiusKm: 20,
        locale: 'zh-CN',
      );

      expect(result, isA<ProviderFactsBundle>());
      expect(transport.uri.path, '/v1/environment/provider-facts');
      expect(transport.uri.queryParameters['radiusKm'], '20');
      expect(transport.headers['Authorization'], 'Bearer token');
    },
  );

  test('rejects responses bound to another coordinate', () async {
    final body = _body();
    final coordinate = Map<String, Object?>.from(
      body['requestedCoordinate']! as Map,
    );
    coordinate['latitude'] = 31.0;
    body['requestedCoordinate'] = coordinate;
    final repository = DataBrokerProviderFactsRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: _FakeTransport(body),
    );
    const point = GeoPoint(
      latitude: 30.25,
      longitude: 120.15,
      coordinateSystem: CoordinateSystem.wgs84,
    );

    await expectLater(repository.fetch(point), throwsFormatException);
  });
}

class _FakeTransport implements ProviderFactsTransport {
  _FakeTransport(this.body);
  final Map<String, Object?> body;
  late Uri uri;
  late Map<String, String> headers;

  @override
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return body;
  }
}

Map<String, Object?> _body() => {
  'contractVersion': 1,
  'requestedCoordinate': {
    'latitude': 30.25,
    'longitude': 120.15,
    'system': 'wgs84',
  },
  'radiusKm': 20,
  'generatedAt': '2026-08-03T08:00:00Z',
  'expiresAt': '2026-08-03T08:30:00Z',
  'status': 'unavailable',
  'cacheStatus': 'miss',
  'providers': <Object?>[],
};
