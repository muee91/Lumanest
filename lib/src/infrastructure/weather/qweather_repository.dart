import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/core/weather/weather_repository.dart';
import 'package:luma_nest/src/infrastructure/weather/qweather_client.dart';

enum WeatherFailureKind { timeout, network, response, malformed }

class WeatherRepositoryFailure implements Exception {
  const WeatherRepositoryFailure(this.kind);

  final WeatherFailureKind kind;

  @override
  String toString() => 'WeatherRepositoryFailure($kind)';
}

class QWeatherRepository implements WeatherRepository {
  const QWeatherRepository(this._client);

  final QWeatherClient _client;

  @override
  Future<WeatherObservation> fetchCurrent(GeoPoint point) async {
    final Map<String, Object?> body;
    try {
      body = await _client.fetchCurrent(point);
    } on QWeatherTransportException catch (error) {
      throw WeatherRepositoryFailure(
        error.kind == QWeatherTransportFailureKind.timeout
            ? WeatherFailureKind.timeout
            : WeatherFailureKind.network,
      );
    }

    if (body['code'] != '200') {
      throw const WeatherRepositoryFailure(WeatherFailureKind.response);
    }
    final now = body['now'];
    if (now is! Map) {
      throw const WeatherRepositoryFailure(WeatherFailureKind.malformed);
    }

    try {
      final values = Map<String, Object?>.from(now);
      final iconCode = int.parse(values['icon']! as String);
      final windGustKilometersPerHour = _optionalDouble(values['windGust']);
      return WeatherObservation(
        observedAt: DateTime.parse(values['obsTime']! as String),
        temperatureCelsius: double.parse(values['temp']! as String),
        condition: _conditionFromIcon(iconCode),
        windSpeedMetersPerSecond:
            double.parse(values['windSpeed']! as String) / 3.6,
        windDirectionDegrees: double.parse(values['wind360']! as String),
        visibilityKilometers: double.parse(values['vis']! as String),
        precipitationMillimeters: double.parse(values['precip']! as String),
        cloudCoverPercent: _optionalDouble(values['cloud']),
        windGustMetersPerSecond: windGustKilometersPerHour == null
            ? null
            : windGustKilometersPerHour / 3.6,
      );
    } on Object {
      throw const WeatherRepositoryFailure(WeatherFailureKind.malformed);
    }
  }

  double? _optionalDouble(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return double.tryParse(value);
  }

  WeatherCondition _conditionFromIcon(int code) {
    if (code == 100) return WeatherCondition.clear;
    if (code >= 101 && code <= 104) return WeatherCondition.cloudy;
    if (code >= 302 && code <= 304) return WeatherCondition.thunder;
    if (code >= 300 && code <= 399) return WeatherCondition.rain;
    if (code >= 400 && code <= 499) return WeatherCondition.snow;
    if (code == 507 || code == 508) return WeatherCondition.dust;
    return WeatherCondition.unknown;
  }
}
