import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';

abstract interface class NarrativeTransport {
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

class DioNarrativeTransport implements NarrativeTransport {
  DioNarrativeTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final response = await _dio.post<Object?>(
      url,
      data: body,
      options: Options(headers: headers),
    );
    if (response.data case final Map raw) {
      return Map<String, Object?>.from(raw);
    }
    throw const FormatException('Invalid narrative response');
  }
}

class DataBrokerManifestNarrativeModel implements ManifestNarrativeModel {
  const DataBrokerManifestNarrativeModel({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final NarrativeTransport transport;

  @override
  Future<ManifestNarrativeCandidate> generate(
    ManifestNarrativeRequest request,
  ) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Narrative broker is not configured');
    }
    final body = await transport.post(
      '$brokerBaseUrl/v1/narrative',
      headers: {'Authorization': 'Bearer $serviceToken'},
      body: {
        'scene': request.scene.name,
        'dayPhase': request.dayPhase.name,
        'weather': request.weather.name,
        'activeRoute': request.activeRoute,
        'creativeEventIds': request.creativeEventIds,
        'templateSummary': request.templateSummary,
        'tone': request.tone.name,
      },
    );
    final summary = body['summary'];
    final rawLabels = body['noteLabels'];
    if (summary is! String || rawLabels is! Map) {
      throw const FormatException('Invalid narrative response');
    }
    final labels = <String, String>{};
    for (final entry in rawLabels.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid narrative labels');
      }
      labels[entry.key as String] = entry.value as String;
    }
    return ManifestNarrativeCandidate(summary: summary, noteLabels: labels);
  }
}
