import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/weather/seven_timer_forecast.dart';
import 'package:luma_nest/src/core/weather/seven_timer_repository.dart';

abstract interface class SevenTimerDataTransport {
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

class DioSevenTimerDataTransport implements SevenTimerDataTransport {
  DioSevenTimerDataTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final response = await _dio.postUri<Object?>(
      uri,
      data: body,
      options: Options(headers: headers),
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid 7Timer response');
    }
    return Map<String, Object?>.from(response.data! as Map);
  }
}

Map<String, Object?>? _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

double? _double(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

SevenTimerRangeValue? _range(Object? value) {
  if (value == null) return null;
  final raw = _map(value);
  final level = raw?['level'];
  final min = raw?['min'];
  final max = raw?['max'];
  final unit = raw?['unit'];
  if (raw == null ||
      level is! int ||
      unit is! String ||
      (min != null && _double(min) == null) ||
      (max != null && _double(max) == null)) {
    throw const FormatException('Invalid 7Timer range');
  }
  return SevenTimerRangeValue(
    level: level,
    min: _double(min),
    max: _double(max),
    unit: unit,
  );
}

SevenTimerWind? _wind(Object? value) {
  if (value == null) return null;
  final raw = _map(value);
  if (raw == null ||
      (raw['direction'] != null && raw['direction'] is! String)) {
    throw const FormatException('Invalid 7Timer wind');
  }
  final speed = _range(raw['speed']);
  final direction = raw['direction'] as String?;
  return direction == null && speed == null
      ? null
      : SevenTimerWind(direction: direction, speed: speed);
}

List<SevenTimerHumidityProfilePoint> _humidityProfile(Object? value) {
  if (value is! List) throw const FormatException('Invalid humidity profile');
  return List.unmodifiable(
    value.map((entry) {
      final raw = _map(entry);
      final layer = raw?['layer'];
      final humidity = _range(raw?['humidity']);
      if (raw == null || layer is! String || humidity == null) {
        throw const FormatException('Invalid humidity profile point');
      }
      return SevenTimerHumidityProfilePoint(layer: layer, humidity: humidity);
    }),
  );
}

List<SevenTimerWindProfilePoint> _windProfile(Object? value) {
  if (value is! List) throw const FormatException('Invalid wind profile');
  return List.unmodifiable(
    value.map((entry) {
      final raw = _map(entry);
      final layer = raw?['layer'];
      final direction = raw?['directionDegrees'];
      if (raw == null ||
          layer is! String ||
          (direction != null && _double(direction) == null)) {
        throw const FormatException('Invalid wind profile point');
      }
      return SevenTimerWindProfilePoint(
        layer: layer,
        directionDegrees: _double(direction),
        speed: _range(raw['speed']),
      );
    }),
  );
}

SevenTimerPrecipitation? _precipitation(Object? value) {
  if (value == null) return null;
  final raw = _map(value);
  if (raw == null || (raw['type'] != null && raw['type'] is! String)) {
    throw const FormatException('Invalid precipitation');
  }
  return SevenTimerPrecipitation(
    type: raw['type'] as String?,
    amount: _range(raw['amount']),
  );
}

SevenTimerPoint _point(Object? value, SevenTimerProduct product) {
  final raw = _map(value);
  final validAt = _date(raw?['validAt']);
  if (raw == null || validAt == null) {
    throw const FormatException('Invalid 7Timer point');
  }
  return switch (product) {
    SevenTimerProduct.astro => SevenTimerAstroPoint(
      validAt: validAt,
      cloudCover: _range(raw['cloudCover']),
      seeing: _range(raw['seeing']),
      transparency: _range(raw['transparency']),
      humidity: _range(raw['humidity']),
      wind: _wind(raw['wind']),
      temperatureCelsius: _double(raw['temperatureCelsius']),
      liftedIndex: _double(raw['liftedIndex']),
      precipitationType: raw['precipitationType'] as String?,
    ),
    SevenTimerProduct.meteo => SevenTimerMeteoPoint(
      validAt: validAt,
      totalCloudCover: _range(raw['totalCloudCover']),
      lowCloudCover: _range(raw['lowCloudCover']),
      middleCloudCover: _range(raw['middleCloudCover']),
      highCloudCover: _range(raw['highCloudCover']),
      humidityProfile: _humidityProfile(raw['humidityProfile']),
      windProfile: _windProfile(raw['windProfile']),
      pressureMslHpa: _double(raw['pressureMslHpa']),
      precipitation: _precipitation(raw['precipitation']),
      snowDepth: _range(raw['snowDepth']),
    ),
    SevenTimerProduct.two => SevenTimerTwoPoint(
      validAt: validAt,
      cloudCover: _range(raw['cloudCover']),
      temperatureMinCelsius: _double(raw['temperatureMinCelsius']),
      temperatureMaxCelsius: _double(raw['temperatureMaxCelsius']),
      humidity: _range(raw['humidity']),
      wind: _wind(raw['wind']),
      liftedIndex: _double(raw['liftedIndex']),
      weatherCode: raw['weatherCode'] as String?,
    ),
  };
}

SevenTimerForecast parseSevenTimerForecast(Map<String, Object?> body) {
  const forbidden = {
    'latitude',
    'longitude',
    'internalScore',
    'providerUrl',
    'redirectUrl',
  };
  if (body.keys.any(forbidden.contains) ||
      body['source'] != '7timer' ||
      body['points'] is! List ||
      body['cacheStatus'] is! String ||
      body['isStaleCache'] is! bool) {
    throw const FormatException('Invalid 7Timer envelope');
  }
  final product = SevenTimerProduct.values
      .where((item) => item.name == body['product'])
      .firstOrNull;
  final sourceStatus = SevenTimerSourceStatus.values
      .where((item) => item.name == body['sourceStatus'])
      .firstOrNull;
  final sourceInitAt = _date(body['sourceInitAt']);
  final fetchedAt = _date(body['fetchedAt']);
  if (product == null ||
      sourceStatus == null ||
      sourceInitAt == null ||
      fetchedAt == null) {
    throw const FormatException('Invalid 7Timer envelope');
  }
  final points = (body['points']! as List)
      .map((value) => _point(value, product))
      .toList(growable: false);
  return SevenTimerForecast(
    product: product,
    sourceInitAt: sourceInitAt,
    fetchedAt: fetchedAt,
    sourceStatus: sourceStatus,
    cacheStatus: body['cacheStatus']! as String,
    isStaleCache: body['isStaleCache']! as bool,
    points: points,
  );
}

class DataBrokerSevenTimerRepository implements SevenTimerRepository {
  const DataBrokerSevenTimerRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final SevenTimerDataTransport transport;

  @override
  Future<SevenTimerForecast?> fetch({
    required double latitude,
    required double longitude,
    required SevenTimerProduct product,
  }) async {
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        brokerBaseUrl.isEmpty ||
        serviceToken.isEmpty) {
      return null;
    }
    try {
      final body = await transport.post(
        Uri.parse(brokerBaseUrl).resolve('/v1/weather/7timer'),
        headers: {'Authorization': 'Bearer $serviceToken'},
        body: {
          'latitude': latitude,
          'longitude': longitude,
          'product': product.name,
        },
      );
      return parseSevenTimerForecast(body);
    } on Object {
      return null;
    }
  }
}
