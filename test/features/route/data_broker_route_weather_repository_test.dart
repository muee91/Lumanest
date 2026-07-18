import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';
import 'package:luma_nest/src/features/route/infrastructure/data_broker_route_weather_repository.dart';

void main() {
  test(
    'posts bounded WGS84 route samples and parses a forecast report',
    () async {
      final transport = _FakeTransport({
        'routeId': 'r1234abcd',
        'generatedAt': '2026-07-18T02:00:00Z',
        'source': 'QWeather',
        'coverage': 'full',
        'requestedSamples': 2,
        'availableSamples': 2,
        'samples': [
          {
            'progress': 0,
            'expectedAt': '2026-07-18T02:10:00Z',
            'forecastAt': '2026-07-18T02:00:00Z',
            'condition': 'clear',
            'cloudCoverPercent': 20,
            'windSpeedMps': 1.5,
            'precipitationMm': 0,
            'visibilityKm': 25,
            'thunder': false,
            'stale': false,
          },
          {
            'progress': 1,
            'expectedAt': '2026-07-18T03:10:00Z',
            'forecastAt': '2026-07-18T03:00:00Z',
            'condition': 'rain',
            'cloudCoverPercent': 90,
            'windSpeedMps': 4,
            'precipitationMm': 2.5,
            'visibilityKm': 8,
            'thunder': true,
            'stale': false,
          },
        ],
      });
      final repository = DataBrokerRouteWeatherRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: transport,
      );
      final corridor = RouteCorridorContext(
        routeId: 'r1234abcd',
        samples: [
          RouteCorridorSample(
            point: const GeoPoint(latitude: 30.25, longitude: 120.15),
            expectedAt: DateTime.parse('2026-07-18T02:10:00Z'),
            progress: 0,
          ),
          RouteCorridorSample(
            point: const GeoPoint(latitude: 30.5, longitude: 120.5),
            expectedAt: DateTime.parse('2026-07-18T03:10:00Z'),
            progress: 1,
          ),
        ],
      );

      final report = await repository.fetch(corridor);

      expect(transport.url, 'https://broker.example.com/v1/route/weather');
      expect(transport.headers, {'Authorization': 'Bearer token'});
      expect(transport.body['routeId'], 'r1234abcd');
      final samples = transport.body['samples']! as List;
      expect(samples, hasLength(2));
      expect(samples.first, containsPair('system', 'wgs84'));
      expect(report.coverage, RouteWeatherCoverage.full);
      expect(report.samples.last.condition, RouteWeatherCondition.rain);
      expect(report.samples.last.thunder, isTrue);
    },
  );

  test('rejects a mismatched route id or malformed coverage', () async {
    final corridor = RouteCorridorContext(
      routeId: 'r1234abcd',
      samples: [
        RouteCorridorSample(
          point: const GeoPoint(latitude: 30, longitude: 120),
          expectedAt: DateTime.utc(2026, 7, 18, 2),
          progress: 0,
        ),
        RouteCorridorSample(
          point: const GeoPoint(latitude: 31, longitude: 121),
          expectedAt: DateTime.utc(2026, 7, 18, 3),
          progress: 1,
        ),
      ],
    );
    final repository = DataBrokerRouteWeatherRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'token',
      transport: _FakeTransport({
        'routeId': 'another-route',
        'generatedAt': '2026-07-18T02:00:00Z',
        'source': 'QWeather',
        'coverage': 'full',
        'requestedSamples': 2,
        'availableSamples': 1,
        'samples': const [],
      }),
    );

    expect(() => repository.fetch(corridor), throwsFormatException);
  });
}

class _FakeTransport implements RouteWeatherTransport {
  _FakeTransport(this.response);

  final Map<String, Object?> response;
  late String url;
  late Map<String, Object?> body;
  late Map<String, String> headers;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    this.url = url;
    this.body = body;
    this.headers = headers;
    return response;
  }
}
