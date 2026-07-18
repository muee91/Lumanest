import 'package:dio/dio.dart';

abstract interface class SkyOpportunityTransport {
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  });
}

class DioSkyOpportunityTransport implements SkyOpportunityTransport {
  DioSkyOpportunityTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final response = await _dio.getUri<Object?>(
      uri,
      options: Options(headers: headers),
    );
    if (response.data is! Map) {
      throw const FormatException('Invalid sky opportunity response');
    }
    return Map<String, Object?>.from(response.data! as Map);
  }
}
