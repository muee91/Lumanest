import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/assistant/assistant_intent.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

enum AssistantAnswerSource { model, template }

enum AssistantFailureKind {
  unconfigured,
  unauthorized,
  invalidRequest,
  snapshotExpired,
  rateLimited,
  timeout,
  network,
  invalidResponse,
  unavailable,
  cancelled,
}

class AssistantFailure implements Exception {
  const AssistantFailure(this.kind, {this.statusCode, this.retryAfterSeconds});

  final AssistantFailureKind kind;
  final int? statusCode;
  final int? retryAfterSeconds;

  @override
  String toString() => 'AssistantFailure(${kind.name}, status: $statusCode)';
}

class AssistantAnswer {
  const AssistantAnswer({
    required this.answer,
    required this.source,
    this.contextEventIds = const [],
    this.expiresAt,
  });

  final String answer;
  final AssistantAnswerSource source;

  /// These ids describe the context supplied to the answer. They are not
  /// presented as sentence-level citations until the server returns fact ids.
  final List<String> contextEventIds;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());
}

abstract interface class AssistantModel {
  Future<AssistantAnswer> answer({
    required ContextSnapshot snapshot,
    required String surface,
    required AssistantIntent intent,
    required List<String> eventIds,
    required NarrativeTone tone,
    Iterable<NearbyPlace> places = const [],
    CancelToken? cancelToken,
  });
}

final assistantModelProvider = Provider<AssistantModel?>((ref) {
  final config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerAssistantModel(
    brokerBaseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
  );
});

class DataBrokerAssistantModel implements AssistantModel {
  DataBrokerAssistantModel({
    required this.brokerBaseUrl,
    required this.serviceToken,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  static const _allowedSurfaces = {
    'today',
    'explore',
    'inspiration',
    'shootingWindow',
  };

  final String brokerBaseUrl;
  final String serviceToken;
  final Dio _dio;

  @override
  Future<AssistantAnswer> answer({
    required ContextSnapshot snapshot,
    required String surface,
    required AssistantIntent intent,
    required List<String> eventIds,
    required NarrativeTone tone,
    Iterable<NearbyPlace> places = const [],
    CancelToken? cancelToken,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const AssistantFailure(AssistantFailureKind.unconfigured);
    }
    if (!_allowedSurfaces.contains(surface) || !intent.allowsRemoteRewrite) {
      throw const AssistantFailure(AssistantFailureKind.invalidRequest);
    }
    // Nearby candidate names are not server-authoritative yet. The official
    // client therefore never transports a place summary to the LLM endpoint.
    if (places.isNotEmpty) {
      throw const AssistantFailure(AssistantFailureKind.invalidRequest);
    }
    try {
      final response = await _dio.post<Object?>(
        '$brokerBaseUrl/v1/assistant',
        data: {
          'snapshotId': snapshot.id,
          'surface': surface,
          'questionType': intent.type.name,
          'eventIds': eventIds
              .where((id) => RegExp(r'^[a-zA-Z0-9._-]{1,96}$').hasMatch(id))
              .take(3)
              .toList(growable: false),
          'tone': tone.name,
          'placeSummaries': const <Object?>[],
        },
        cancelToken: cancelToken,
        options: Options(
          headers: {'Authorization': 'Bearer $serviceToken'},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode != 200) {
        throw _failureForResponse(response);
      }
      final raw = response.data;
      if (raw is! Map || raw['answer'] is! String || raw['source'] is! String) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      final answer = (raw['answer']! as String).trim();
      final source = switch (raw['source']) {
        'model' => AssistantAnswerSource.model,
        'template' => AssistantAnswerSource.template,
        _ => throw const AssistantFailure(AssistantFailureKind.invalidResponse),
      };
      if (answer.isEmpty || answer.runes.length > 80 || RegExp(r'https?://|[\r\n]').hasMatch(answer)) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      final contextIds = raw['usedFactIds'] ?? raw['citedEventIds'];
      final expiresAt = raw['expiresAt'];
      final result = AssistantAnswer(
        answer: answer,
        source: source,
        contextEventIds: contextIds is List
            ? contextIds
                  .whereType<String>()
                  .where((id) => RegExp(r'^[a-zA-Z0-9._-]{1,96}$').hasMatch(id))
                  .take(12)
                  .toList(growable: false)
            : const [],
        expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt)?.toUtc() : null,
      );
      if (result.isExpired) {
        throw const AssistantFailure(
          AssistantFailureKind.snapshotExpired,
          statusCode: 410,
        );
      }
      return result;
    } on AssistantFailure {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const AssistantFailure(AssistantFailureKind.cancelled);
      }
      if (error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionTimeout) {
        throw const AssistantFailure(AssistantFailureKind.timeout);
      }
      throw const AssistantFailure(AssistantFailureKind.network);
    } on FormatException {
      throw const AssistantFailure(AssistantFailureKind.invalidResponse);
    }
  }

  AssistantFailure _failureForResponse(Response<Object?> response) {
    final status = response.statusCode;
    final error = _errorCode(response.data);
    final retryAfter = int.tryParse(response.headers.value('retry-after') ?? '');
    final kind = switch (status) {
      400 => AssistantFailureKind.invalidRequest,
      401 || 403 => AssistantFailureKind.unauthorized,
      410 => AssistantFailureKind.snapshotExpired,
      429 => AssistantFailureKind.rateLimited,
      503 when error == 'ai_unconfigured' => AssistantFailureKind.unconfigured,
      502 || 503 => AssistantFailureKind.unavailable,
      _ => AssistantFailureKind.unavailable,
    };
    return AssistantFailure(
      kind,
      statusCode: status,
      retryAfterSeconds: retryAfter,
    );
  }

  String? _errorCode(Object? raw) {
    if (raw is! Map) return null;
    final error = raw['error'];
    if (error is String) return error;
    if (error is Map && error['code'] is String) {
      return error['code'] as String;
    }
    return null;
  }
}
