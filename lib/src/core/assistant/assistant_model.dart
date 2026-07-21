import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/assistant/assistant_intent.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';

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
    this.degradedReason,
    this.webSources = const [],
  });

  final String answer;
  final AssistantAnswerSource source;

  /// These ids describe the context supplied to the answer. They are not
  /// presented as sentence-level citations until the server returns fact ids.
  final List<String> contextEventIds;
  final DateTime? expiresAt;

  /// Set when the broker attempted a model rewrite but fell back to the
  /// deterministic template answer (e.g. 'rate_limited', 'invalid_response',
  /// 'model_unavailable'). Null when the model answered or was never
  /// attempted.
  final String? degradedReason;
  final List<AssistantWebSource> webSources;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());
}

/// Progressive events emitted while the broker streams an assistant answer.
/// The broker only ever streams guard-validated text, so [AssistantStreamDelta]
/// fragments are safe to render as they arrive. [AssistantStreamDone] carries
/// the finalized [AssistantAnswer] (source / expiry / degraded reason).
sealed class AssistantStreamEvent {
  const AssistantStreamEvent();
}

/// The broker accepted the request and is routing it to a model profile.
class AssistantStreamThinking implements AssistantStreamEvent {
  const AssistantStreamThinking();
}

/// The first upstream token arrived; the model is actively generating.
class AssistantStreamGenerating implements AssistantStreamEvent {
  const AssistantStreamGenerating();
}

/// A grounded fragment of the final answer, safe to render immediately.
class AssistantStreamDelta implements AssistantStreamEvent {
  const AssistantStreamDelta(this.text);

  final String text;
}

/// The stream completed; [answer] is the finalized, validated answer.
class AssistantStreamDone implements AssistantStreamEvent {
  const AssistantStreamDone(this.answer);

  final AssistantAnswer answer;
}

/// One prior turn of the same conversation, sent so the broker can resolve
/// follow-ups like “那明天呢？”. The broker stays stateless: history travels
/// with every request and is bounded by [assistantHistoryLimit].
class AssistantHistoryTurn {
  const AssistantHistoryTurn({required this.question, required this.answer});

  final String question;
  final String answer;
}

/// Maximum prior turns transported to the broker; mirrors the server bound.
const int assistantHistoryLimit = 8;

abstract interface class AssistantModel {
  Stream<AssistantStreamEvent> answerStream({
    required ContextSnapshot snapshot,
    required String surface,
    required AssistantIntent intent,
    required List<String> eventIds,
    required NarrativeTone tone,
    String? conversationId,
    List<AssistantHistoryTurn> history = const [],
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
  Stream<AssistantStreamEvent> answerStream({
    required ContextSnapshot snapshot,
    required String surface,
    required AssistantIntent intent,
    required List<String> eventIds,
    required NarrativeTone tone,
    String? conversationId,
    List<AssistantHistoryTurn> history = const [],
    CancelToken? cancelToken,
  }) async* {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const AssistantFailure(AssistantFailureKind.unconfigured);
    }
    if (!_allowedSurfaces.contains(surface) || !intent.allowsRemoteRewrite) {
      throw const AssistantFailure(AssistantFailureKind.invalidRequest);
    }
    final boundedContextIds = _boundedContextIds(
      snapshot: snapshot,
      intent: intent,
      requestedIds: eventIds,
    );
    final allowedContextIds = boundedContextIds.toSet();
    final boundedConversationId = _boundedConversationId(conversationId);
    final boundedHistory = _boundedHistory(history);

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '$brokerBaseUrl/v1/assistant',
        data: {
          'snapshotId': snapshot.id,
          'surface': surface,
          'questionType': intent.type.name,
          if (intent.normalizedQuestion.isNotEmpty)
            'question': intent.normalizedQuestion,
          'eventIds': boundedContextIds,
          'tone': tone.name,
          'location': ?_amapLocation(snapshot.location),
          'conversationId': ?boundedConversationId,
          if (boundedHistory.isNotEmpty)
            'history': [
              for (final turn in boundedHistory)
                {'question': turn.question, 'answer': turn.answer},
            ],
        },
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Authorization': 'Bearer $serviceToken',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
          sendTimeout: const Duration(seconds: 8),
          // Streaming keeps the connection open while the model generates, so
          // the receive budget is larger than the old single-shot 8s call.
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw _mapDioException(error);
    }

    // Validation failures (400/410/...) are still plain JSON, not SSE.
    if (response.statusCode != 200 || response.data == null) {
      throw await _failureFromStreamResponse(response);
    }

    yield* _decodeEventStream(
      response.data!.stream,
      allowedContextIds: allowedContextIds,
    );
  }

  /// Exposed only to let protocol tests exercise malformed/truncated SSE
  /// streams without opening a socket.
  Stream<AssistantStreamEvent> decodeEventStreamForTesting(
    Stream<List<int>> stream, {
    Set<String> allowedContextIds = const {},
  }) => _decodeEventStream(stream, allowedContextIds: allowedContextIds);

  Stream<AssistantStreamEvent> _decodeEventStream(
    Stream<List<int>> stream, {
    required Set<String> allowedContextIds,
  }) async* {
    final answerBuffer = StringBuffer();
    String? eventName;
    final dataBuffer = StringBuffer();
    AssistantStreamDone? terminalEvent;
    try {
      final lines = utf8.decoder.bind(stream).transform(const LineSplitter());
      await for (final line in lines) {
        if (line.isEmpty) {
          final name = eventName;
          final data = dataBuffer.toString();
          eventName = null;
          dataBuffer.clear();
          if (name == null || data.isEmpty) continue;
          if (terminalEvent != null) {
            throw const AssistantFailure(AssistantFailureKind.invalidResponse);
          }
          if (name == 'status') {
            final phase = _stringField(data, 'phase');
            if (phase == 'thinking') yield const AssistantStreamThinking();
            if (phase == 'generating') yield const AssistantStreamGenerating();
          } else if (name == 'delta') {
            final text = _stringField(data, 'text');
            if (text != null && text.isNotEmpty) {
              answerBuffer.write(text);
              yield AssistantStreamDelta(text);
            }
          } else if (name == 'error') {
            throw AssistantFailure(_streamFailureKind(data));
          } else if (name == 'done') {
            terminalEvent = _buildDone(
              data,
              answerBuffer.toString(),
              allowedContextIds,
            );
          }
        } else if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
          dataBuffer.write(line.substring(5).trim());
        }
      }
      if (terminalEvent == null) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      yield terminalEvent;
    } on AssistantFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const AssistantFailure(AssistantFailureKind.invalidResponse);
    }
  }

  /// The broker only accepts a bounded opaque id, so anything outside the
  /// contract is dropped rather than rejected — history degrades gracefully.
  String? _boundedConversationId(String? value) {
    if (value == null) return null;
    return RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(value) ? value : null;
  }

  /// GCJ-02 "lng,lat" for the broker's own Amap lookup. Place names are never
  /// sent by the client anymore; the broker derives them server-side, so this
  /// point is the only location input the assistant contract carries. The
  /// client owns the single WGS84 → GCJ-02 conversion boundary.
  String? _amapLocation(GeoPoint? point) {
    if (point == null) return null;
    final mapPoint = point.coordinateSystem == CoordinateSystem.wgs84
        ? ChinaCoordinateConverter.wgs84ToGcj02(point)
        : point;
    return '${mapPoint.longitude},${mapPoint.latitude}';
  }

  /// Keeps the most recent [assistantHistoryLimit] turns that fit the broker
  /// contract verbatim. Oversized turns (e.g. multi-line shooting plans) are
  /// skipped, never truncated, so the model only sees text shown as-is.
  List<AssistantHistoryTurn> _boundedHistory(List<AssistantHistoryTurn> turns) {
    final bounded = turns
        .where(
          (turn) =>
              turn.question.isNotEmpty &&
              turn.question.length <= 240 &&
              turn.answer.isNotEmpty &&
              turn.answer.length <= 200,
        )
        .toList(growable: false);
    return bounded.length <= assistantHistoryLimit
        ? bounded
        : bounded.sublist(bounded.length - assistantHistoryLimit);
  }

  List<String> _boundedContextIds({
    required ContextSnapshot snapshot,
    required AssistantIntent intent,
    required Iterable<String> requestedIds,
  }) {
    final knownIds = <String>{
      for (final event in snapshot.events) event.id,
      for (final session in snapshot.shootingSessions) session.id,
    };
    final selected = requestedIds
        .where(knownIds.contains)
        .where((id) => RegExp(r'^[a-zA-Z0-9._-]{1,96}$').hasMatch(id))
        .take(3)
        .toList(growable: true);
    final requiresSession = switch (intent.type) {
      AssistantQuestionType.why ||
      AssistantQuestionType.prepare ||
      AssistantQuestionType.timing ||
      AssistantQuestionType.creative => true,
      _ => false,
    };
    if (selected.isEmpty && requiresSession) {
      final now = DateTime.now().toUtc();
      final session = snapshot.shootingSessions
          .where((item) => item.expiresAt.isAfter(now))
          .firstOrNull;
      if (session != null) selected.add(session.id);
    }
    return List.unmodifiable(selected.take(3));
  }

  AssistantFailure _mapDioException(DioException error) {
    if (CancelToken.isCancel(error)) {
      return const AssistantFailure(AssistantFailureKind.cancelled);
    }
    if (error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionTimeout) {
      return const AssistantFailure(AssistantFailureKind.timeout);
    }
    return const AssistantFailure(AssistantFailureKind.network);
  }

  /// Non-200 responses are plain JSON error bodies even though the request was
  /// made in streaming mode, so the body is drained and decoded here.
  Future<AssistantFailure> _failureFromStreamResponse(
    Response<ResponseBody> response,
  ) async {
    final status = response.statusCode;
    final retryAfter = int.tryParse(
      response.headers.value('retry-after') ?? '',
    );
    String? error;
    try {
      final body = response.data;
      if (body != null) {
        final bytes = <int>[];
        await for (final chunk in body.stream) {
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
        error = _errorCode(decoded);
      }
    } on Object {
      error = null;
    }
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

  /// Builds the terminal event from the SSE `done` payload plus the answer
  /// accumulated from `delta` fragments, applying the same bounds the broker
  /// enforces so a malformed stream can never surface an unbounded answer.
  AssistantStreamDone _buildDone(
    String data,
    String accumulated,
    Set<String> allowedContextIds,
  ) {
    final raw = _decodeJson(data);
    if (raw == null) {
      throw const AssistantFailure(AssistantFailureKind.invalidResponse);
    }
    final answer = accumulated.trim();
    final source = switch (raw['source']) {
      'model' => AssistantAnswerSource.model,
      'template' => AssistantAnswerSource.template,
      _ => throw const AssistantFailure(AssistantFailureKind.invalidResponse),
    };
    if (answer.isEmpty ||
        answer.runes.length > 200 ||
        RegExp(r'https?://|[\r\n]').hasMatch(answer)) {
      throw const AssistantFailure(AssistantFailureKind.invalidResponse);
    }
    final contextIds = raw['usedFactIds'] ?? raw['citedEventIds'];
    final expiresAt = raw['expiresAt'];
    final degraded = raw['degraded'];
    final webSources = _webSources(raw['sources']);
    final result = AssistantAnswer(
      answer: answer,
      source: source,
      contextEventIds: contextIds is List
          ? contextIds
                .whereType<String>()
                .where(allowedContextIds.contains)
                .take(12)
                .toList(growable: false)
          : const [],
      expiresAt: expiresAt is String
          ? DateTime.tryParse(expiresAt)?.toUtc()
          : null,
      degradedReason:
          source == AssistantAnswerSource.template && degraded is String
          ? degraded
          : null,
      webSources: webSources,
    );
    if (result.isExpired) {
      throw const AssistantFailure(
        AssistantFailureKind.snapshotExpired,
        statusCode: 410,
      );
    }
    return AssistantStreamDone(result);
  }

  AssistantFailureKind _streamFailureKind(String data) {
    final error = _decodeJson(data)?['error'];
    return switch (error) {
      'rate_limited' => AssistantFailureKind.rateLimited,
      'timeout' => AssistantFailureKind.timeout,
      'ai_unconfigured' => AssistantFailureKind.unconfigured,
      _ => AssistantFailureKind.unavailable,
    };
  }

  List<AssistantWebSource> _webSources(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > 4) {
      throw const AssistantFailure(AssistantFailureKind.invalidResponse);
    }
    final sources = <AssistantWebSource>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      final title = item['title'];
      final publisher = item['publisher'];
      final url = item['url'];
      final parsed = url is String ? Uri.tryParse(url) : null;
      if (title is! String ||
          title.trim().isEmpty ||
          title.runes.length > 200 ||
          publisher is! String ||
          publisher.trim().isEmpty ||
          publisher.runes.length > 120 ||
          parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      sources.add(
        AssistantWebSource(
          title: title.trim(),
          publisher: publisher.trim(),
          url: parsed,
        ),
      );
    }
    return List.unmodifiable(sources);
  }

  Map<String, Object?>? _decodeJson(String data) {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on Object {
      return null;
    }
  }

  String? _stringField(String data, String field) {
    final value = _decodeJson(data)?[field];
    return value is String ? value : null;
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
