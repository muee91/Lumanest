import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class AssistantAnswer {
  const AssistantAnswer({
    required this.answer,
    required this.source,
    this.citedEventIds = const [],
    this.expiresAt,
  });

  final String answer;
  final String source;
  final List<String> citedEventIds;
  final DateTime? expiresAt;
}

abstract interface class AssistantModel {
  Future<AssistantAnswer> answer({
    required ContextSnapshot snapshot,
    required String surface,
    required String questionType,
    required List<String> eventIds,
    required NarrativeTone tone,
    Iterable<NearbyPlace> places = const [],
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

  final String brokerBaseUrl;
  final String serviceToken;
  final Dio _dio;

  @override
  Future<AssistantAnswer> answer({
    required ContextSnapshot snapshot,
    required String surface,
    required String questionType,
    required List<String> eventIds,
    required NarrativeTone tone,
    Iterable<NearbyPlace> places = const [],
  }) async {
    final response = await _dio.post<Object?>(
      '$brokerBaseUrl/v1/assistant',
      data: {
        'snapshotId': snapshot.id,
        'surface': surface,
        'questionType': questionType,
        'eventIds': eventIds,
        'tone': tone.name,
        'placeSummaries': [
          for (final place in places.take(8))
            {
              'name': place.name,
              'category': place.category.name,
              'distanceMeters': place.distanceMeters,
            },
        ],
      },
      options: Options(
        headers: {'Authorization': 'Bearer $serviceToken'},
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final raw = response.data;
    if (raw is! Map || raw['answer'] is! String || raw['source'] is! String) {
      throw const FormatException('Invalid assistant response');
    }
    final cited = raw['citedEventIds'];
    final expiresAt = raw['expiresAt'];
    return AssistantAnswer(
      answer: (raw['answer']! as String).trim(),
      source: raw['source']! as String,
      citedEventIds: cited is List
          ? cited.whereType<String>().toList(growable: false)
          : const [],
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
    );
  }
}
