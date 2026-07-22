import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';

class _FakeTransport implements SiteEnvironmentTransport {
  _FakeTransport(this.body);

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

Map<String, Object?> _body({
  required double requestedLatitude,
  required double requestedLongitude,
}) => {
  'contractVersion': 2,
  'requestedCoordinate': {
    'latitude': requestedLatitude,
    'longitude': requestedLongitude,
    'system': 'wgs84',
  },
  'terrain': {
    'status': 'ready',
    'elevationMeters': 126.0,
    'sampledCoordinate': {
      'latitude': 30.25,
      'longitude': 120.15,
      'system': 'wgs84',
    },
    'generatedAt': '2026-07-22T12:00:00Z',
    'expiresAt': '2026-10-20T12:00:00Z',
    'cacheStatus': 'hit',
    'source': {
      'id': 'open-meteo-elevation',
      'dataset': 'Copernicus DEM GLO-90 2021',
      'revision': 'copernicus-dem-glo90-2021',
      'resolutionMeters': 90,
      'attribution': 'Copernicus DEM · Open-Meteo',
    },
  },
  'nightSkyBackground': {
    'status': 'ready',
    'radiance': 0.42,
    'radianceUnit': 'nW/cm2/sr',
    'relativeRadianceBand': 'dark',
    'classificationVersion': 'viirs-relative-radiance.1',
    'datasetYear': 2024,
    'datasetRevision': 'eog-v2.2-2024-median-masked-r1',
    'resolutionMeters': 500,
    'sampledCoordinate': {
      'latitude': 30.2505,
      'longitude': 120.1505,
      'system': 'wgs84',
    },
    'generatedAt': '2026-07-22T12:00:00Z',
    'expiresAt': '2026-08-21T12:00:00Z',
    'cacheStatus': 'hit',
    'source': {
      'id': 'eog-viirs-annual-v2.2',
      'revision': 'eog-v2.2-2024-median-masked-r1',
      'attribution': 'Earth Observation Group',
    },
  },
  'generatedAt': '2026-07-22T12:00:00Z',
};

void main() {
  test('accepts a response explicitly bound to the requested coordinate', () async {
    const point = GeoPoint(latitude: 30.2502, longitude: 120.1502);
    final transport = _FakeTransport(
      _body(
        requestedLatitude: point.latitude,
        requestedLongitude: point.longitude,
      ),
    );
    final repository = DataBrokerSiteEnvironmentRepository(
      brokerBaseUrl: 'https://broker.internal',
      serviceToken: 'service-token',
      transport: transport,
    );

    final facts = await repository.fetch(point);

    expect(facts.requestedCoordinate.latitude, point.latitude);
    expect(transport.requestedUri?.path, '/v1/environment/site-facts');
    expect(transport.requestedUri?.queryParameters['lat'], '${point.latitude}');
    expect(
      transport.requestedHeaders,
      {'Authorization': 'Bearer service-token'},
    );
  });

  test('rejects a cached response bound to another requested coordinate', () async {
    const point = GeoPoint(latitude: 30.2502, longitude: 120.1502);
    final transport = _FakeTransport(
      _body(requestedLatitude: 30.251, requestedLongitude: 120.151),
    );
    final repository = DataBrokerSiteEnvironmentRepository(
      brokerBaseUrl: 'https://broker.internal',
      serviceToken: 'service-token',
      transport: transport,
    );

    expect(repository.fetch(point), throwsFormatException);
  });
}
