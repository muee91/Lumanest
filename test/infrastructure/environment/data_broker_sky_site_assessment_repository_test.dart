import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_sky_site_assessment_repository.dart';

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
  double latitude = 30.2502,
  double longitude = 120.1502,
}) => {
  'contractVersion': 4,
  'requestedCoordinate': {
    'latitude': latitude,
    'longitude': longitude,
    'system': 'wgs84',
  },
  'terrain': <String, Object?>{},
  'nightSkyBackground': <String, Object?>{},
  'generatedAt': '2026-07-23T16:00:01.000Z',
  'observedAt': '2026-07-23T16:00:00.000Z',
  'terrainHorizon': {
    'status': 'unconfigured',
    'algorithmVersion': 'terrain-horizon-radial.1',
    'datasetRevision': null,
    'resolutionMeters': null,
    'observer': null,
    'azimuthStepDegrees': 5,
    'maximumDistanceKm': 40,
    'sampleSpacingMeters': null,
    'refractionCoefficient': 0.13,
    'coverageRatio': null,
    'samples': <Object?>[],
    'sampledCoordinate': {
      'latitude': 30.25,
      'longitude': 120.15,
      'system': 'wgs84',
    },
    'generatedAt': '2026-07-23T16:00:01.000Z',
    'expiresAt': '2026-07-23T16:05:01.000Z',
    'cacheStatus': 'miss',
    'source': null,
  },
  'skySiteAssessment': {
    'status': 'ready',
    'conditionBand': 'insufficientData',
    'algorithmVersion': 'sky-site-assessment.1',
    'observedAt': '2026-07-23T16:00:00.000Z',
    'geometry': {
      'galacticCenter': {
        'azimuthDegrees': 142.0,
        'altitudeDegrees': 18.2,
        'modelVersion': 'iau-galactic-center-j2000.1',
      },
      'sun': {
        'azimuthDegrees': 10.0,
        'altitudeDegrees': -25.0,
        'modelVersion': 'solar-position-low-precision.1',
      },
      'astronomicalNight': true,
    },
    'terrain': {'status': 'unconfigured'},
    'lightPollution': {'status': 'unavailable'},
    'limitations': [
      'terrain_horizon_unavailable',
      'directional_light_pollution_unavailable',
    ],
  },
};

void main() {
  test('requests a time-bound assessment from the environment route', () async {
    const point = GeoPoint(latitude: 30.2502, longitude: 120.1502);
    final transport = _FakeTransport(_body());
    final repository = DataBrokerSkySiteAssessmentRepository(
      brokerBaseUrl: 'https://broker.internal',
      serviceToken: 'service-token',
      transport: transport,
    );

    final envelope = await repository.fetch(
      point,
      observedAt: DateTime.parse('2026-07-23T16:00:00Z'),
    );

    expect(envelope.requestedCoordinate.latitude, point.latitude);
    expect(transport.requestedUri?.path, '/v1/environment/site-facts');
    expect(transport.requestedUri?.queryParameters['include'], 'skyAssessment');
    expect(
      transport.requestedUri?.queryParameters['at'],
      '2026-07-23T16:00:00.000Z',
    );
    expect(
      transport.requestedHeaders,
      {'Authorization': 'Bearer service-token'},
    );
  });

  test('rejects a response bound to another coordinate', () async {
    const point = GeoPoint(latitude: 30.2502, longitude: 120.1502);
    final repository = DataBrokerSkySiteAssessmentRepository(
      brokerBaseUrl: 'https://broker.internal',
      serviceToken: 'service-token',
      transport: _FakeTransport(_body(latitude: 30.251)),
    );

    await expectLater(
      repository.fetch(
        point,
        observedAt: DateTime.parse('2026-07-23T16:00:00Z'),
      ),
      throwsFormatException,
    );
  });
}
