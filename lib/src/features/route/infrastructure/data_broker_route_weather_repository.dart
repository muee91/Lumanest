import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';

abstract interface class RouteWeatherTransport {
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  });
}

class DioRouteWeatherTransport implements RouteWeatherTransport {
  DioRouteWeatherTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    final response = await _dio.post<Object?>(
      url,
      data: body,
      options: Options(headers: headers),
    );
    if (response.data case final Map value) {
      return Map<String, Object?>.from(value);
    }
    throw const FormatException('Invalid route weather response');
  }
}

class DataBrokerRouteWeatherRepository implements RouteWeatherRepository {
  const DataBrokerRouteWeatherRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final RouteWeatherTransport transport;

  @override
  Future<RouteWeatherReport> fetch(RouteCorridorContext corridor) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Route weather broker is not configured');
    }
    if (!corridor.isUsable ||
        corridor.samples.length < 2 ||
        corridor.samples.length > 5) {
      throw const FormatException('Route weather sample count is out of range');
    }
    final body = await transport.post(
      '$brokerBaseUrl/v1/route/weather',
      body: {
        'routeId': corridor.routeId,
        'samples': corridor.samples
            .map((sample) => sample.toRequest())
            .toList(growable: false),
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    return _parse(body, expectedRouteId: corridor.routeId);
  }

  RouteWeatherReport _parse(
    Map<String, Object?> body, {
    required String expectedRouteId,
  }) {
    final routeId = body['routeId'];
    final generatedAt = DateTime.tryParse(body['generatedAt'] as String? ?? '');
    final source = body['source'];
    final coverage = switch (body['coverage']) {
      'full' => RouteWeatherCoverage.full,
      'partial' => RouteWeatherCoverage.partial,
      _ => null,
    };
    final requestedSamples = body['requestedSamples'];
    final availableSamples = body['availableSamples'];
    final rawSamples = body['samples'];
    if (routeId != expectedRouteId ||
        generatedAt == null ||
        source is! String ||
        source.isEmpty ||
        coverage == null ||
        requestedSamples is! int ||
        requestedSamples < 2 ||
        requestedSamples > 5 ||
        availableSamples is! int ||
        availableSamples < 1 ||
        availableSamples > requestedSamples ||
        rawSamples is! List ||
        rawSamples.length != availableSamples) {
      throw const FormatException('Invalid route weather report');
    }
    final samples = <RouteWeatherSample>[];
    var previousProgress = -1.0;
    for (final raw in rawSamples) {
      if (raw is! Map) {
        throw const FormatException('Invalid route weather sample');
      }
      final sample = Map<String, Object?>.from(raw);
      final progress = (sample['progress'] as num?)?.toDouble();
      final expectedAt = DateTime.tryParse(
        sample['expectedAt'] as String? ?? '',
      );
      final forecastAt = DateTime.tryParse(
        sample['forecastAt'] as String? ?? '',
      );
      final condition = _condition(sample['condition']);
      final cloudCover = _nullableFinite(sample['cloudCoverPercent'], 0, 100);
      final windSpeed = _finite(sample['windSpeedMps'], 0, 150);
      final precipitation = _finite(sample['precipitationMm'], 0, 2000);
      final visibility = _nullableFinite(sample['visibilityKm'], 0, 500);
      final thunder = sample['thunder'];
      final stale = sample['stale'];
      if (progress == null ||
          !progress.isFinite ||
          progress < 0 ||
          progress > 1 ||
          progress <= previousProgress ||
          expectedAt == null ||
          forecastAt == null ||
          condition == null ||
          windSpeed == null ||
          precipitation == null ||
          thunder is! bool ||
          stale is! bool) {
        throw const FormatException('Invalid route weather sample');
      }
      samples.add(
        RouteWeatherSample(
          progress: progress,
          expectedAt: expectedAt,
          forecastAt: forecastAt,
          condition: condition,
          cloudCoverPercent: cloudCover,
          windSpeedMps: windSpeed,
          precipitationMm: precipitation,
          visibilityKm: visibility,
          thunder: thunder,
          stale: stale,
        ),
      );
      previousProgress = progress;
    }
    if (coverage == RouteWeatherCoverage.full &&
        availableSamples != requestedSamples) {
      throw const FormatException('Invalid route weather coverage');
    }
    return RouteWeatherReport(
      routeId: routeId as String,
      generatedAt: generatedAt,
      source: source,
      coverage: coverage,
      requestedSamples: requestedSamples,
      availableSamples: availableSamples,
      samples: samples,
    );
  }

  RouteWeatherCondition? _condition(Object? value) => switch (value) {
    'clear' => RouteWeatherCondition.clear,
    'cloudy' => RouteWeatherCondition.cloudy,
    'rain' => RouteWeatherCondition.rain,
    'snow' => RouteWeatherCondition.snow,
    'dust' => RouteWeatherCondition.dust,
    'unknown' => RouteWeatherCondition.unknown,
    _ => null,
  };

  double? _finite(Object? value, double minimum, double maximum) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite && result >= minimum && result <= maximum
        ? result
        : null;
  }

  double? _nullableFinite(Object? value, double minimum, double maximum) =>
      value == null ? null : _finite(value, minimum, maximum);
}
