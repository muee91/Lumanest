import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/companion/companion_client.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

void main() {
  test('inventory strictly parses the current insight contract', () async {
    final adapter = _RecordingAdapter(
      (options) => {
        'targetSize': 36,
        'minimumSize': 20,
        'maximumSize': 60,
        'items': [_wireInsight()],
        'nextCursor': null,
      },
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = DataBrokerCompanionRepository(
      baseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      dio: dio,
    );

    final inventory = await repository.inventory();

    expect(inventory, hasLength(1));
    expect(inventory.single.geoScope, ContextGeoScope.point);
    expect(inventory.single.opportunityInstanceId, 'opportunity_12345678');
    expect(
      adapter.requests.single.uri.toString(),
      'https://broker.example/v1/inspiration/inventory?limit=60',
    );
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer service-token',
    );
  });

  test(
    'unknown or malformed inventory fields fail the whole response',
    () async {
      for (final item in <Map<String, Object?>>[
        {..._wireInsight(), 'fact': 'model-invented'},
        {..._wireInsight(), 'confidence': 1.1},
        {
          ..._wireInsight(),
          'sources': [
            {
              ...(_wireInsight()['sources']! as List).single as Map,
              'url': 'http://insecure.example/source',
            },
          ],
        },
      ]) {
        final dio = Dio()
          ..httpClientAdapter = _RecordingAdapter(
            (_) => {
              'items': [item],
            },
          );
        final repository = DataBrokerCompanionRepository(
          baseUrl: 'https://broker.example',
          serviceToken: 'token',
          dio: dio,
        );
        await expectLater(repository.inventory(), throwsFormatException);
      }
    },
  );

  test('wildlife and non-bottle insights never become inspiration notes', () {
    final now = DateTime.utc(2026, 7, 18, 10);
    expect(
      _insight(
        channel: InsightChannel.wildlifeOpportunity,
      ).toInspirationNote(now),
      isNull,
    );
    expect(_insight(canEnterBottle: false).toInspirationNote(now), isNull);
  });

  test(
    'refresh and feedback send authorization and idempotency headers',
    () async {
      final adapter = _RecordingAdapter(
        (options) => options.path.endsWith('/refresh')
            ? <String, Object?>{}
            : <String, Object?>{'accepted': true},
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DataBrokerCompanionRepository(
        baseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        dio: dio,
      );

      await repository.refresh(
        snapshotId: 'ctx_1234567890abcdef12345678',
        reason: 'manual_refresh',
        visiblePage: 'today',
      );
      await repository.feedback(
        'insight_1234567890abcdef12345678',
        InsightFeedbackAction.notInterested,
      );

      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(request.headers['Authorization'], 'Bearer service-token');
        expect(
          request.headers['Idempotency-Key'],
          matches(RegExp(r'^app-[a-f0-9]{32}$')),
        );
      }
      expect(adapter.requests.last.data, {'action': 'not_interested'});
    },
  );

  test('controller keeps the last inventory when the Broker fails', () async {
    final repository = _FlakyRepository(_insight());
    final container = ProviderContainer(
      overrides: [companionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(companionInventoryProvider.future);

    final notifier = container.read(companionInventoryProvider.notifier);
    await notifier.refresh(
      snapshotId: 'ctx_1234567890abcdef12345678',
      reason: 'manual_refresh',
      visiblePage: 'inspiration',
    );
    expect(
      container.read(companionInventoryProvider).requireValue,
      hasLength(1),
    );

    repository.fail = true;
    await notifier.refresh(
      snapshotId: 'ctx_1234567890abcdef12345678',
      reason: 'manual_refresh',
      visiblePage: 'inspiration',
    );
    expect(
      container.read(companionInventoryProvider).requireValue,
      hasLength(1),
    );
  });
}

Map<String, Object?> _wireInsight() => {
  'id': 'insight_1234567890abcdef12345678',
  'channel': 'photographyOpportunity',
  'title': '湖岸晚间会话',
  'body': '风和光线正在形成湖岸晚间拍摄窗口',
  'shortLabel': '湖岸晚光',
  'emoji': '🌇',
  'generatedAt': '2026-07-18T10:00:00Z',
  'startsAt': '2026-07-18T10:00:00Z',
  'peaksAt': '2026-07-18T10:30:00Z',
  'expiresAt': '2026-07-18T11:00:00Z',
  'geoScope': 'point',
  'confidence': .9,
  'priority': 70,
  'action': 'openShootingWindow',
  'sources': [
    {
      'id': 'qweather',
      'label': '结构化环境数据',
      'observedAt': '2026-07-18T10:00:00Z',
      'url': 'https://example.test/source',
    },
  ],
  'canEnterBottle': true,
  'canNotify': false,
  'opportunityInstanceId': 'opportunity_12345678',
  'targetId': 'target_12345678',
  'routeId': null,
  'sessionId': 'session_12345678',
  'searchMissionId': null,
};

CompanionInsight _insight({
  InsightChannel channel = InsightChannel.photographyOpportunity,
  bool canEnterBottle = true,
}) => CompanionInsight(
  id: 'insight_1234567890abcdef12345678',
  channel: channel,
  title: '当前机会',
  body: '只使用已经成立的结构化事实。',
  shortLabel: '当前机会',
  emoji: '📷',
  generatedAt: DateTime.utc(2026, 7, 18, 10),
  startsAt: DateTime.utc(2026, 7, 18, 10),
  expiresAt: DateTime.utc(2026, 7, 18, 11),
  geoScope: ContextGeoScope.region,
  confidence: .9,
  priority: 70,
  action: ManifestAction.openShootingWindow,
  sources: const [],
  canEnterBottle: canEnterBottle,
  canNotify: false,
);

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.response);

  final Map<String, Object?> Function(RequestOptions options) response;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FlakyRepository implements CompanionRepository {
  _FlakyRepository(this.item);

  final CompanionInsight item;
  bool fail = false;

  @override
  Future<void> feedback(String insightId, InsightFeedbackAction action) async {}

  @override
  Future<List<CompanionInsight>> inventory() async {
    if (fail) throw StateError('offline');
    return [item];
  }

  @override
  Future<void> refresh({
    required String snapshotId,
    required String reason,
    required String visiblePage,
    String? routeId,
  }) async {
    if (fail) throw StateError('offline');
  }
}
