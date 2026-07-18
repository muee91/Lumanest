import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';

enum InsightChannel {
  photographyOpportunity,
  localDiscovery,
  humanityClue,
  creativePrompt,
  routeCompanion,
  lifeCompanion,
  memoryFollowUp,
  wildlifeOpportunity,
}

enum InsightFeedbackAction {
  viewed,
  dismissed,
  saved,
  routed,
  started,
  completed,
  notInterested,
}

class CompanionSourceReference {
  const CompanionSourceReference({
    required this.id,
    required this.label,
    required this.observedAt,
    this.url,
  });

  final String id;
  final String label;
  final DateTime observedAt;
  final Uri? url;
}

class CompanionInsight {
  const CompanionInsight({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.shortLabel,
    required this.emoji,
    required this.generatedAt,
    required this.startsAt,
    required this.expiresAt,
    required this.geoScope,
    required this.confidence,
    required this.priority,
    required this.action,
    required this.sources,
    required this.canEnterBottle,
    required this.canNotify,
    this.peaksAt,
    this.opportunityInstanceId,
    this.targetId,
    this.routeId,
    this.sessionId,
    this.searchMissionId,
  });

  final String id;
  final InsightChannel channel;
  final String title;
  final String body;
  final String shortLabel;
  final String emoji;
  final DateTime generatedAt;
  final DateTime startsAt;
  final DateTime? peaksAt;
  final DateTime expiresAt;
  final ContextGeoScope geoScope;
  final double confidence;
  final int priority;
  final ManifestAction action;
  final List<CompanionSourceReference> sources;
  final bool canEnterBottle;
  final bool canNotify;
  final String? opportunityInstanceId;
  final String? targetId;
  final String? routeId;
  final String? sessionId;
  final String? searchMissionId;

  InspirationNote? toInspirationNote(DateTime now) {
    if (!canEnterBottle || !expiresAt.isAfter(now.toUtc())) return null;
    if (channel == InsightChannel.wildlifeOpportunity) return null;
    return InspirationNote(
      id: id,
      label: shortLabel,
      emoji: emoji,
      category: switch (channel) {
        InsightChannel.creativePrompt => InspirationCategory.composition,
        InsightChannel.localDiscovery ||
        InsightChannel.humanityClue ||
        InsightChannel.routeCompanion ||
        InsightChannel.lifeCompanion ||
        InsightChannel.memoryFollowUp => InspirationCategory.place,
        InsightChannel.photographyOpportunity => InspirationCategory.light,
        InsightChannel.wildlifeOpportunity => InspirationCategory.place,
      },
      kind: channel == InsightChannel.creativePrompt
          ? InspirationNoteKind.creativePrompt
          : InspirationNoteKind.factualOpportunity,
      action: action,
      detail: body,
      priority: priority,
      ttl: expiresAt.difference(now.toUtc()),
      opportunityId: opportunityInstanceId ?? sessionId,
      evidence: sources.map((source) => source.label).toList(growable: false),
    );
  }
}

abstract interface class CompanionRepository {
  Future<void> refresh({
    required String snapshotId,
    required String reason,
    required String visiblePage,
    String? routeId,
  });
  Future<List<CompanionInsight>> inventory();
  Future<void> feedback(String insightId, InsightFeedbackAction action);
}

class DataBrokerCompanionRepository implements CompanionRepository {
  DataBrokerCompanionRepository({
    required this.baseUrl,
    required this.serviceToken,
    required this.dio,
  });

  final String baseUrl;
  final String serviceToken;
  final Dio dio;

  @override
  Future<void> refresh({
    required String snapshotId,
    required String reason,
    required String visiblePage,
    String? routeId,
  }) async {
    await dio.postUri<Object?>(
      Uri.parse(baseUrl).resolve('/v1/companion/refresh'),
      data: {
        'snapshotId': snapshotId,
        'reason': reason,
        'routeId': routeId,
        'visiblePage': visiblePage,
        'localTimeZone': DateTime.now().timeZoneName.contains('/')
            ? DateTime.now().timeZoneName
            : 'Asia/Shanghai',
      },
      options: Options(headers: _headers(_key(snapshotId, reason))),
    );
  }

  @override
  Future<List<CompanionInsight>> inventory() async {
    final response = await dio.getUri<Object?>(
      Uri.parse(baseUrl).resolve('/v1/inspiration/inventory?limit=60'),
      options: Options(headers: _headers()),
    );
    final body = response.data;
    if (body is! Map || body['items'] is! List) {
      throw const FormatException('Invalid companion inventory');
    }
    final rawItems = body['items']! as List;
    if (rawItems.length > 60) {
      throw const FormatException('Invalid companion inventory size');
    }
    final values = <CompanionInsight>[];
    for (final raw in rawItems) {
      final item = _parseInsight(raw);
      if (item == null) {
        throw const FormatException('Invalid companion inventory item');
      }
      if (item.canEnterBottle) values.add(item);
    }
    return List.unmodifiable(values);
  }

  @override
  Future<void> feedback(String insightId, InsightFeedbackAction action) async {
    final wireAction = action == InsightFeedbackAction.notInterested
        ? 'not_interested'
        : action.name;
    await dio.postUri<Object?>(
      Uri.parse(baseUrl).resolve('/v1/insights/$insightId/feedback'),
      data: {'action': wireAction},
      options: Options(headers: _headers(_key(insightId, wireAction))),
    );
  }

  Map<String, String> _headers([String? idempotencyKey]) {
    final headers = <String, String>{'Authorization': 'Bearer $serviceToken'};
    if (idempotencyKey != null) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    return headers;
  }

  String _key(String id, String action) =>
      'app-${sha256.convert(utf8.encode('$id\u0000$action\u0000${DateTime.now().millisecondsSinceEpoch ~/ 30000}')).toString().substring(0, 32)}';

  CompanionInsight? _parseInsight(Object? raw) {
    const keys = <String>{
      'id',
      'channel',
      'title',
      'body',
      'shortLabel',
      'emoji',
      'generatedAt',
      'startsAt',
      'peaksAt',
      'expiresAt',
      'geoScope',
      'confidence',
      'priority',
      'action',
      'sources',
      'canEnterBottle',
      'canNotify',
      'opportunityInstanceId',
      'targetId',
      'routeId',
      'sessionId',
      'searchMissionId',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.any((key) => !keys.contains(key))) {
      return null;
    }
    try {
      final channel = InsightChannel.values.byName('${raw['channel']}');
      final action = ManifestAction.values.byName('${raw['action']}');
      final geoScope = ContextGeoScope.values.byName('${raw['geoScope']}');
      final generatedAt = DateTime.parse('${raw['generatedAt']}').toUtc();
      final startsAt = DateTime.parse('${raw['startsAt']}').toUtc();
      final peaksAt = raw['peaksAt'] == null
          ? null
          : DateTime.parse('${raw['peaksAt']}').toUtc();
      final expiresAt = DateTime.parse('${raw['expiresAt']}').toUtc();
      if (!_boundedString(raw['id'], 96) ||
          !_boundedString(raw['title'], 120) ||
          !_boundedString(raw['body'], 280) ||
          !_boundedString(raw['shortLabel'], 32) ||
          !_boundedString(raw['emoji'], 16) ||
          !expiresAt.isAfter(startsAt) ||
          (peaksAt != null &&
              (peaksAt.isBefore(startsAt) || peaksAt.isAfter(expiresAt))) ||
          raw['confidence'] is! num ||
          (raw['confidence']! as num).toDouble() < 0 ||
          (raw['confidence']! as num).toDouble() > 1 ||
          raw['priority'] is! int ||
          (raw['priority']! as int) < 0 ||
          (raw['priority']! as int) > 100 ||
          raw['sources'] is! List ||
          (raw['sources']! as List).length > 6 ||
          raw['canEnterBottle'] is! bool ||
          raw['canNotify'] is! bool ||
          !_nullableId(raw['opportunityInstanceId']) ||
          !_nullableId(raw['targetId']) ||
          !_nullableId(raw['routeId']) ||
          !_nullableId(raw['sessionId']) ||
          !_nullableId(raw['searchMissionId'])) {
        return null;
      }
      final sources = <CompanionSourceReference>[];
      for (final value in raw['sources']! as List) {
        final source = _parseSource(value);
        if (source == null) return null;
        sources.add(source);
      }
      return CompanionInsight(
        id: '${raw['id']}',
        channel: channel,
        title: '${raw['title']}',
        body: '${raw['body']}',
        shortLabel: '${raw['shortLabel']}',
        emoji: '${raw['emoji']}',
        generatedAt: generatedAt,
        startsAt: startsAt,
        peaksAt: peaksAt,
        expiresAt: expiresAt,
        geoScope: geoScope,
        confidence: (raw['confidence']! as num).toDouble(),
        priority: raw['priority']! as int,
        action: action,
        sources: List.unmodifiable(sources),
        canEnterBottle: raw['canEnterBottle']! as bool,
        canNotify: raw['canNotify']! as bool,
        opportunityInstanceId: raw['opportunityInstanceId'] as String?,
        targetId: raw['targetId'] as String?,
        routeId: raw['routeId'] as String?,
        sessionId: raw['sessionId'] as String?,
        searchMissionId: raw['searchMissionId'] as String?,
      );
    } on Object {
      return null;
    }
  }

  CompanionSourceReference? _parseSource(Object? raw) {
    const keys = <String>{'id', 'label', 'observedAt', 'url'};
    if (raw is! Map ||
        raw.keys.any((key) => !keys.contains(key)) ||
        !raw.containsKey('id') ||
        !raw.containsKey('label') ||
        !raw.containsKey('observedAt')) {
      return null;
    }
    try {
      final uri = raw['url'] == null ? null : Uri.parse('${raw['url']}');
      if (uri != null && (uri.scheme != 'https' || uri.host.isEmpty)) {
        return null;
      }
      if (!_boundedString(raw['id'], 80) ||
          !_boundedString(raw['label'], 100)) {
        return null;
      }
      return CompanionSourceReference(
        id: '${raw['id']}',
        label: '${raw['label']}',
        observedAt: DateTime.parse('${raw['observedAt']}').toUtc(),
        url: uri,
      );
    } on Object {
      return null;
    }
  }

  static bool _boundedString(Object? value, int maximum) =>
      value is String &&
      value.trim().isNotEmpty &&
      value.runes.length <= maximum;

  static bool _nullableId(Object? value) =>
      value == null ||
      (value is String &&
          RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$').hasMatch(value));
}

final companionRepositoryProvider = Provider<CompanionRepository?>((ref) {
  final EnvironmentConfig config = ref.watch(environmentConfigProvider);
  if (!config.isDataBrokerConfigured) return null;
  return DataBrokerCompanionRepository(
    baseUrl: config.dataBrokerBaseUrl,
    serviceToken: config.lumaNestServiceToken,
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 5),
      ),
    ),
  );
});

class CompanionInventoryController
    extends AsyncNotifier<List<CompanionInsight>> {
  @override
  Future<List<CompanionInsight>> build() async => const [];

  Future<void> refresh({
    required String snapshotId,
    required String reason,
    required String visiblePage,
    String? routeId,
  }) async {
    final repository = ref.read(companionRepositoryProvider);
    if (repository == null) return;
    try {
      await repository.refresh(
        snapshotId: snapshotId,
        reason: reason,
        visiblePage: visiblePage,
        routeId: routeId,
      );
      state = AsyncData(await repository.inventory());
    } on Object {
      // Local deterministic inventory remains available when Companion is down.
    }
  }

  Future<void> feedback(String insightId, InsightFeedbackAction action) async {
    final repository = ref.read(companionRepositoryProvider);
    if (repository == null) return;
    try {
      await repository.feedback(insightId, action);
    } on Object {
      // Feedback is best-effort and never blocks the local action.
    }
  }
}

final companionInventoryProvider =
    AsyncNotifierProvider<CompanionInventoryController, List<CompanionInsight>>(
      CompanionInventoryController.new,
    );
