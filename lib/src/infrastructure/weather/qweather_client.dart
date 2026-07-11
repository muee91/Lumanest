import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

enum QWeatherTransportFailureKind { timeout, network }

class QWeatherTransportException implements Exception {
  const QWeatherTransportException(this.kind);

  const QWeatherTransportException.timeout()
    : kind = QWeatherTransportFailureKind.timeout;

  const QWeatherTransportException.network()
    : kind = QWeatherTransportFailureKind.network;

  final QWeatherTransportFailureKind kind;
}

abstract interface class QWeatherTransport {
  Future<Map<String, Object?>> get(
    String path, {
    required String baseUrl,
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioQWeatherTransport implements QWeatherTransport {
  DioQWeatherTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    String path, {
    required String baseUrl,
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        '$baseUrl$path',
        queryParameters: query,
        options: Options(headers: headers),
      );
      final data = response.data;
      if (data is! Map) return const {};
      return Map<String, Object?>.from(data);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const QWeatherTransportException.timeout();
      }
      throw const QWeatherTransportException.network();
    }
  }
}

class QWeatherClient {
  factory QWeatherClient({
    required String apiHost,
    required String apiKey,
    required QWeatherTransport transport,
  }) {
    return QWeatherClient._(apiHost, apiKey, transport);
  }

  const QWeatherClient._(this._apiHost, this._apiKey, this._transport);

  final String _apiHost;
  final String _apiKey;
  final QWeatherTransport _transport;

  Future<Map<String, Object?>> fetchCurrent(GeoPoint point) {
    point.validate();
    return _transport.get(
      '/v7/weather/now',
      baseUrl: _apiHost,
      query: {'location': '${point.longitude},${point.latitude}'},
      headers: {'X-QW-Api-Key': _apiKey},
    );
  }
}
