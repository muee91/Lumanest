import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';
import 'package:luma_nest/src/features/route/infrastructure/data_broker_route_weather_repository.dart';

void main() {
  test(
    'parses bounded corridor references and authoritative restrictions',
    () async {
      final repository = DataBrokerRouteWeatherRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: _Transport(_response()),
      );

      final report = await repository.fetch(_corridor());

      expect(report.corridor, isNotNull);
      expect(report.corridor!.coverage, RouteCorridorCoverage.full);
      expect(report.corridor!.segments.first.facilities.parking, 2);
      expect(
        report.corridor!.segments.first.restrictions.status,
        RouteRestrictionStatus.present,
      );
      expect(report.corridor!.hasAuthoritativeRestrictions, isTrue);
      expect(
        report.corridor!.segments.last.restrictions.status,
        RouteRestrictionStatus.noneObserved,
      );
    },
  );

  test('rejects corridor schema expansion with precise coordinates', () async {
    final response = _response();
    final corridor = response['corridor']! as Map<String, Object?>;
    final segments = corridor['segments']! as List<Object?>;
    final first = Map<String, Object?>.from(segments.first! as Map);
    first['latitude'] = 30.25;
    segments[0] = first;
    final repository = DataBrokerRouteWeatherRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'token',
      transport: _Transport(response),
    );

    expect(() => repository.fetch(_corridor()), throwsFormatException);
  });
}

RouteCorridorContext _corridor() => RouteCorridorContext(
  routeId: 'r1234abcd',
  samples: [
    RouteCorridorSample(
      point: const GeoPoint(latitude: 30.25, longitude: 120.15),
      expectedAt: DateTime.parse('2026-08-05T06:10:00Z'),
      progress: 0,
    ),
    RouteCorridorSample(
      point: const GeoPoint(latitude: 30.5, longitude: 120.5),
      expectedAt: DateTime.parse('2026-08-05T07:10:00Z'),
      progress: 1,
    ),
  ],
);

Map<String, Object?> _response() => {
  'routeId': 'r1234abcd',
  'generatedAt': '2026-08-05T06:00:00Z',
  'source': 'QWeather',
  'coverage': 'full',
  'requestedSamples': 2,
  'availableSamples': 2,
  'samples': [
    {
      'progress': 0,
      'expectedAt': '2026-08-05T06:10:00Z',
      'forecastAt': '2026-08-05T06:00:00Z',
      'condition': 'clear',
      'cloudCoverPercent': 20,
      'windSpeedMps': 2,
      'precipitationMm': 0,
      'visibilityKm': 25,
      'thunder': false,
      'stale': false,
    },
    {
      'progress': 1,
      'expectedAt': '2026-08-05T07:10:00Z',
      'forecastAt': '2026-08-05T07:00:00Z',
      'condition': 'cloudy',
      'cloudCoverPercent': 70,
      'windSpeedMps': 4,
      'precipitationMm': 0,
      'visibilityKm': 18,
      'thunder': false,
      'stale': false,
    },
  ],
  'corridor': <String, Object?>{
    'contractVersion': 1,
    'generatedAt': '2026-08-05T06:00:00Z',
    'coverage': 'full',
    'requestedSegments': 2,
    'availableSegments': 2,
    'sources': [
      {
        'id': 'openstreetmap-overpass',
        'title': 'OpenStreetMap Overpass API',
        'publisher': 'OpenStreetMap contributors',
        'url': 'https://www.openstreetmap.org/copyright',
        'license': 'ODbL-1.0',
        'version': 'Overpass QL',
      },
      {
        'id': 'official-notices',
        'title': 'Official notices',
        'publisher': 'Road authority',
        'url': 'https://example.gov/notices',
        'license': null,
        'version': null,
      },
    ],
    'segments': <Object?>[
      {
        'progress': 0,
        'expectedAt': '2026-08-05T06:10:00Z',
        'facilities': {
          'status': 'reference',
          'parking': 2,
          'fuel': 1,
          'food': 0,
          'water': 1,
          'toilets': 0,
          'shelter': 0,
          'restArea': 0,
        },
        'photography': {
          'status': 'reference',
          'viewpointCount': 1,
          'heritageCount': 0,
        },
        'restrictions': {
          'status': 'present',
          'kinds': ['roadClosure'],
          'authoritative': true,
          'factIds': ['notice-1'],
        },
        'evidence': {
          'status': 'verified',
          'factIds': ['map-1', 'notice-1'],
        },
      },
      {
        'progress': 1,
        'expectedAt': '2026-08-05T07:10:00Z',
        'facilities': {
          'status': 'empty',
          'parking': 0,
          'fuel': 0,
          'food': 0,
          'water': 0,
          'toilets': 0,
          'shelter': 0,
          'restArea': 0,
        },
        'photography': {
          'status': 'noReference',
          'viewpointCount': 0,
          'heritageCount': 0,
        },
        'restrictions': {
          'status': 'noneObserved',
          'kinds': <String>[],
          'authoritative': false,
          'factIds': <String>[],
        },
        'evidence': {'status': 'unavailable', 'factIds': <String>[]},
      },
    ],
    'limitations': [
      'public_map_inventory_is_reference_only',
      'absence_of_official_notice_is_not_safety_confirmation',
      'precise_route_geometry_excluded',
    ],
  },
};

class _Transport implements RouteWeatherTransport {
  _Transport(this.response);

  final Map<String, Object?> response;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async => response;
}
