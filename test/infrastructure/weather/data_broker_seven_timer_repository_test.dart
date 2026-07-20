import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/weather/seven_timer_forecast.dart';
import 'package:luma_nest/src/infrastructure/weather/data_broker_seven_timer_repository.dart';

void main() {
  test('posts coordinates through the broker and parses ASTRO', () async {
    final transport = _Transport(_response('astro', [_astroPoint()]));
    final repository = DataBrokerSevenTimerRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: transport,
    );

    final value = await repository.fetch(
      latitude: 30.274,
      longitude: 120.155,
      product: SevenTimerProduct.astro,
    );

    expect(transport.uri.path, '/v1/weather/7timer');
    expect(transport.headers, {'Authorization': 'Bearer token'});
    expect(transport.body, {
      'latitude': 30.274,
      'longitude': 120.155,
      'product': 'astro',
    });
    expect(value?.product, SevenTimerProduct.astro);
    final point = value!.points.single as SevenTimerAstroPoint;
    expect(point.cloudCover?.level, 3);
    expect(point.cloudCover?.min, 19);
    expect(point.seeing?.unit, 'arcsec');
  });

  test('parses METEO profiles and nullable ranges', () async {
    final repository = _repository(
      _response('meteo', [
        {
          'validAt': '2026-07-19T06:00:00.000Z',
          'totalCloudCover': null,
          'lowCloudCover': _range(4, 31, 44, 'percent'),
          'middleCloudCover': null,
          'highCloudCover': null,
          'humidityProfile': [
            {'layer': '950mb', 'humidity': _range(11, 75, 80, 'percent')},
          ],
          'windProfile': [
            {
              'layer': '500mb',
              'directionDegrees': 215,
              'speed': _range(10, 41.4, 46.2, 'mps'),
            },
          ],
          'pressureMslHpa': 1002,
          'precipitation': {
            'type': 'rain',
            'amount': _range(3, 1, 4, 'mm_per_hour'),
          },
          'snowDepth': null,
        },
      ]),
    );

    final value = await repository.fetch(
      latitude: 1,
      longitude: 2,
      product: SevenTimerProduct.meteo,
    );
    final point = value!.points.single as SevenTimerMeteoPoint;
    expect(point.totalCloudCover, isNull);
    expect(point.humidityProfile.single.layer, '950mb');
    expect(point.windProfile.single.speed?.level, 10);
    expect(point.precipitation?.amount?.max, 4);
  });

  test('parses TWO without treating missing values as zero', () async {
    final repository = _repository(
      _response('two', [
        {
          'validAt': '2026-07-27T12:00:00.000Z',
          'cloudCover': null,
          'temperatureMinCelsius': null,
          'temperatureMaxCelsius': 29,
          'humidity': _range(13, 85, 90, 'percent'),
          'wind': null,
          'liftedIndex': -1,
          'weatherCode': 'clear',
        },
      ]),
    );

    final value = await repository.fetch(
      latitude: 1,
      longitude: 2,
      product: SevenTimerProduct.two,
    );
    final point = value!.points.single as SevenTimerTwoPoint;
    expect(point.temperatureMinCelsius, isNull);
    expect(point.temperatureMaxCelsius, 29);
    expect(point.wind, isNull);
    expect(point.weatherCode, 'clear');
  });

  test(
    'returns null for configuration, transport and contract failures',
    () async {
      expect(
        await DataBrokerSevenTimerRepository(
          brokerBaseUrl: '',
          serviceToken: '',
          transport: _Transport(_response('astro', [_astroPoint()])),
        ).fetch(latitude: 1, longitude: 2, product: SevenTimerProduct.astro),
        isNull,
      );

      expect(
        await _repository({
          'source': '7timer',
        }).fetch(latitude: 1, longitude: 2, product: SevenTimerProduct.astro),
        isNull,
      );

      expect(
        await DataBrokerSevenTimerRepository(
          brokerBaseUrl: 'https://broker.example',
          serviceToken: 'token',
          transport: _ThrowingTransport(),
        ).fetch(latitude: 1, longitude: 2, product: SevenTimerProduct.astro),
        isNull,
      );
    },
  );

  test('rejects forbidden provider and coordinate fields', () {
    final body = _response('astro', [_astroPoint()]);
    body['latitude'] = 30.274;
    expect(() => parseSevenTimerForecast(body), throwsFormatException);
  });
}

DataBrokerSevenTimerRepository _repository(Map<String, Object?> response) =>
    DataBrokerSevenTimerRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: _Transport(response),
    );

Map<String, Object?> _response(
  String product,
  List<Map<String, Object?>> points,
) => {
  'source': '7timer',
  'product': product,
  'sourceInitAt': '2026-07-19T00:00:00.000Z',
  'fetchedAt': '2026-07-19T06:00:00.000Z',
  'sourceStatus': 'fresh',
  'cacheStatus': 'miss',
  'isStaleCache': false,
  'points': points,
};

Map<String, Object?> _astroPoint() => {
  'validAt': '2026-07-19T03:00:00.000Z',
  'cloudCover': _range(3, 19, 31, 'percent'),
  'seeing': _range(4, 1, 1.25, 'arcsec'),
  'transparency': _range(3, .4, .5, 'mag_per_airmass'),
  'humidity': _range(11, 75, 80, 'percent'),
  'wind': {'direction': 'E', 'speed': _range(2, .3, 3.4, 'mps')},
  'temperatureCelsius': 26,
  'liftedIndex': 2,
  'precipitationType': 'none',
};

Map<String, Object?> _range(int level, num? min, num? max, String unit) => {
  'level': level,
  'min': min,
  'max': max,
  'unit': unit,
};

class _Transport implements SevenTimerDataTransport {
  _Transport(this.response);

  final Map<String, Object?> response;
  late Uri uri;
  late Map<String, String> headers;
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return response;
  }
}

class _ThrowingTransport implements SevenTimerDataTransport {
  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) => throw Exception('offline');
}
