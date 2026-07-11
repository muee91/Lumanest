import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_client.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_repository.dart';

void main() {
  late _FakeTransport transport;
  late QWeatherRepository repository;

  setUp(() {
    transport = _FakeTransport();
    transport.postResponse = {'token': 'header.payload.signature'};
    repository = QWeatherRepository(
      QWeatherClient(
        apiHost: 'https://weather.example.com',
        tokenEndpoint: 'https://broker.example.com/v1/qweather/token',
        serviceToken: 'broker-secret',
        transport: transport,
      ),
    );
  });

  test('requests a broker JWT then uses it for the weather request', () async {
    transport.response = _successBody();

    await repository.fetchCurrent(
      const GeoPoint(latitude: 31.2304, longitude: 121.4737),
    );

    expect(transport.path, '/v7/weather/now');
    expect(transport.baseUrl, 'https://weather.example.com');
    expect(transport.query, {'location': '121.4737,31.2304'});
    expect(transport.postBaseUrl, 'https://broker.example.com/v1/qweather/token');
    expect(transport.postHeaders, {'Authorization': 'Bearer broker-secret'});
    expect(transport.headers, {'Authorization': 'Bearer header.payload.signature'});
  });

  test('parses QWeather units and optional fields', () async {
    transport.response = _successBody();

    final observation = await repository.fetchCurrent(
      const GeoPoint(latitude: 31.2304, longitude: 121.4737),
    );

    expect(observation.condition, WeatherCondition.clear);
    expect(observation.temperatureCelsius, 26);
    expect(observation.windSpeedMetersPerSecond, closeTo(5, 0.001));
    expect(observation.windDirectionDegrees, 180);
    expect(observation.visibilityKilometers, 20);
    expect(observation.cloudCoverPercent, 12);
  });

  test('maps a non-success API code to a safe response failure', () async {
    transport.response = {'code': '401'};

    expect(
      () => repository.fetchCurrent(
        const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      ),
      throwsA(
        isA<WeatherRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          WeatherFailureKind.response,
        ),
      ),
    );
  });

  test('maps malformed bodies without exposing the body', () async {
    transport.response = {'code': '200', 'now': 'not-an-object'};

    expect(
      () => repository.fetchCurrent(
        const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      ),
      throwsA(
        isA<WeatherRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          WeatherFailureKind.malformed,
        ),
      ),
    );
  });

  test('maps transport timeout to a timeout failure', () async {
    transport.error = const QWeatherTransportException.timeout();

    expect(
      () => repository.fetchCurrent(
        const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      ),
      throwsA(
        isA<WeatherRepositoryFailure>().having(
          (failure) => failure.kind,
          'kind',
          WeatherFailureKind.timeout,
        ),
      ),
    );
  });
}

Map<String, Object?> _successBody() {
  return {
    'code': '200',
    'now': {
      'obsTime': '2026-07-11T19:56+08:00',
      'temp': '26',
      'icon': '100',
      'wind360': '180',
      'windSpeed': '18',
      'vis': '20',
      'precip': '0.0',
      'cloud': '12',
    },
  };
}

class _FakeTransport implements QWeatherTransport {
  Map<String, Object?>? response;
  QWeatherTransportException? error;
  Map<String, Object?>? postResponse;
  String? postBaseUrl;
  Map<String, String>? postHeaders;
  String? path;
  String? baseUrl;
  Map<String, String>? query;
  Map<String, String>? headers;

  @override
  Future<Map<String, Object?>> get(
    String path, {
    required String baseUrl,
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    this.path = path;
    this.baseUrl = baseUrl;
    this.query = query;
    this.headers = headers;
    if (error case final error?) throw error;
    return response!;
  }

  @override
  Future<Map<String, Object?>> post(
    String path, {
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    postBaseUrl = '$baseUrl$path';
    postHeaders = headers;
    if (error case final error?) throw error;
    return postResponse!;
  }
}
