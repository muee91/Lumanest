import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/safety_detail.dart';

bool _isBoundedText(Object? value, int maximum) =>
    value is String && value.trim().isNotEmpty && value.length <= maximum;

bool _isIsoTimestamp(Object? value) =>
    value is String && DateTime.tryParse(value) != null;

abstract interface class SafetyDetailTransport {
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

class DioSafetyDetailTransport implements SafetyDetailTransport {
  DioSafetyDetailTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        url,
        data: body,
        options: Options(headers: headers),
      );
      if (response.data case final Map data) {
        return Map<String, Object?>.from(data);
      }
      throw const FormatException('Invalid safety detail response');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return const {};
      throw const FormatException('Safety detail request failed');
    }
  }
}

class DataBrokerSafetyDetailRepository implements SafetyDetailRepository {
  const DataBrokerSafetyDetailRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final SafetyDetailTransport transport;

  @override
  Future<SafetyDetail?> fetch({
    required String contextId,
    required String eventId,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) return null;
    final body = await transport.post(
      '$brokerBaseUrl/v1/context/safety-detail',
      headers: {'Authorization': 'Bearer $serviceToken'},
      body: {'contextId': contextId, 'eventId': eventId},
    );
    if (body.isEmpty) return null;
    const keys = {
      'eventId',
      'title',
      'description',
      'guidance',
      'source',
      'severity',
      'observedAt',
      'expiresAt',
      'contextId',
    };
    final guidance = body['guidance'];
    if (body.keys.any((key) => !keys.contains(key)) ||
        body['eventId'] != eventId ||
        body['contextId'] != contextId ||
        !_isBoundedText(body['title'], 80) ||
        !_isBoundedText(body['description'], 500) ||
        guidance is! List ||
        guidance.length > 3 ||
        guidance.any((item) => !_isBoundedText(item, 160)) ||
        !_isBoundedText(body['source'], 80) ||
        !const {
          'info',
          'caution',
          'warning',
          'critical',
        }.contains(body['severity']) ||
        !_isIsoTimestamp(body['observedAt']) ||
        !_isIsoTimestamp(body['expiresAt'])) {
      throw const FormatException('Invalid safety detail response');
    }
    return SafetyDetail(
      eventId: eventId,
      title: body['title']! as String,
      description: body['description']! as String,
      guidance: List.unmodifiable(guidance.cast<String>()),
    );
  }
}
