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

  Future<Map<String, Object?>> post(
    String path, {
    required String baseUrl,
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

  @override
  Future<Map<String, Object?>> post(
    String path, {
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        '$baseUrl$path',
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
    required String tokenEndpoint,
    required String serviceToken,
    required QWeatherTransport transport,
  }) {
    return QWeatherClient._(apiHost, tokenEndpoint, serviceToken, transport);
  }

  const QWeatherClient._(
    this._apiHost,
    this._tokenEndpoint,
    this._serviceToken,
    this._transport,
  );

  final String _apiHost;
  final String _tokenEndpoint;
  final String _serviceToken;
  final QWeatherTransport _transport;

  Future<Map<String, Object?>> fetchCurrent(GeoPoint point) async {
    point.validate();
    final brokerResponse = await _transport.post(
      '',
      baseUrl: _tokenEndpoint,
      headers: {'Authorization': 'Bearer $_serviceToken'},
    );
    final token = brokerResponse['token'];
    if (token is! String || token.split('.').length != 3) {
      throw const QWeatherTransportException.network();
    }
    return _transport.get(
      '/v7/weather/now',
      baseUrl: _apiHost,
      query: {'location': '${point.longitude},${point.latitude}'},
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
