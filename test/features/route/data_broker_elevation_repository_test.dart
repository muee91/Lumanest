import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/infrastructure/data_broker_elevation_repository.dart';

void main() {
  test(
    'requests a bounded broker profile and parses numeric elevations',
    () async {
      final transport = _FakeTransport({
        'source': 'Open-Meteo Elevation API',
        'elevations': [5, 21],
      });
      final repository = DataBrokerElevationProfileRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: transport,
      );

      final profile = await repository.fetch(const [
        GeoPoint(latitude: 31.23, longitude: 121.47),
        GeoPoint(latitude: 31.24, longitude: 121.48),
      ]);

      expect(transport.url, 'https://broker.example.com/v1/elevation/profile');
      expect(transport.query['locations'], '121.47,31.23;121.48,31.24');
      expect(profile.elevations, [5, 21]);
    },
  );

  test('rejects missing or mismatched elevation values', () async {
    final repository = DataBrokerElevationProfileRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'token',
      transport: _FakeTransport({
        'source': 'source',
        'elevations': [5],
      }),
    );

    expect(
      () => repository.fetch(const [
        GeoPoint(latitude: 31.23, longitude: 121.47),
        GeoPoint(latitude: 31.24, longitude: 121.48),
      ]),
      throwsFormatException,
    );
  });
}

class _FakeTransport implements ElevationProfileTransport {
  _FakeTransport(this.response);
  final Map<String, Object?> response;
  late String url;
  late Map<String, String> query;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    this.url = url;
    this.query = query;
    return response;
  }
}
