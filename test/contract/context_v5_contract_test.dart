import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';

/// The client is the third copy of the V5 contract, and the one that fails
/// last: a field the context service adds reaches a shipped app that rejects
/// the whole response. These checks bind the parser to the same golden body and
/// policy numbers that `app/v5.py` and the broker proxy are held to.
class _GoldenTransport implements ContextDataTransport {
  _GoldenTransport(this.response);

  final Map<String, Object?> response;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async => Map.of(response);
}

void main() {
  final policy = jsonDecode(
    File('contract/context-v5.policy.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final golden = jsonDecode(
    File('contract/context-v5.snapshot.golden.json').readAsStringSync(),
  ) as Map<String, Object?>;

  LocationReading location() => LocationReading(
    point: const GeoPoint(latitude: 30.25, longitude: 120.15),
    recordedAt: DateTime.utc(2026, 7, 14, 2),
    accuracyMeters: 8,
  );

  Future<ContextSnapshot> parse(Map<String, Object?> body) =>
      DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: _GoldenTransport(body),
      ).fetchSnapshot(location: location(), observedAt: DateTime.utc(2026, 7, 14, 2));

  test('生产响应原样可解析', () async {
    final snapshot = await parse(golden);

    expect(golden['contractVersion'], policy['contractVersion']);
    expect(snapshot.entries, isNotEmpty, reason: 'golden 必须带着真实条目');
    expect(snapshot.entries.length, (golden['entries'] as List).length);
  });

  test('每个 entry 的字段都逐项映射，退化到默认值会被发现', () async {
    // Length and non-emptiness were the only assertions, so a parser that
    // mapped every entry to defaults still passed. Each field is now compared
    // against the golden body the broker and the context service are held to.
    final snapshot = await parse(golden);
    final expected = (golden['entries'] as List).cast<Map<String, Object?>>();
    expect(snapshot.entries.length, expected.length);
    for (var index = 0; index < expected.length; index += 1) {
      final raw = expected[index];
      final entry = snapshot.entries[index];
      expect(entry.id, raw['id'], reason: 'entry[$index].id');
      expect(entry.kind.name, raw['kind'], reason: 'entry[$index].kind');
      expect(
        entry.sourceNamespace,
        raw['sourceNamespace'],
        reason: 'entry[$index].sourceNamespace',
      );
      expect(entry.sourceId, raw['sourceId'], reason: 'entry[$index].sourceId');
      expect(entry.revision, raw['revision'], reason: 'entry[$index].revision');
      expect(
        entry.observedAt,
        DateTime.parse(raw['observedAt']! as String),
        reason: 'entry[$index].observedAt',
      );
      expect(
        entry.validFrom,
        DateTime.parse(raw['validFrom']! as String),
        reason: 'entry[$index].validFrom',
      );
      expect(
        entry.expiresAt,
        DateTime.parse(raw['expiresAt']! as String),
        reason: 'entry[$index].expiresAt',
      );
      expect(
        entry.freshness.name,
        raw['freshness'],
        reason: 'entry[$index].freshness',
      );
      expect(
        entry.evidenceConfidence,
        (raw['evidenceConfidence']! as num).toDouble(),
        reason: 'entry[$index].evidenceConfidence',
      );
      expect(
        entry.basePriority.name,
        raw['basePriority'],
        reason: 'entry[$index].basePriority',
      );
      expect(
        entry.severity.name,
        raw['severity'],
        reason: 'entry[$index].severity',
      );
      expect(
        entry.geoScope.type.name,
        raw['geoScope'],
        reason: 'entry[$index].geoScope',
      );
      expect(
        entry.allowedSurfaces.map((surface) => surface.name).toSet(),
        (raw['allowedSurfaces']! as List).cast<String>().toSet(),
        reason: 'entry[$index].allowedSurfaces',
      );
      expect(
        entry.actions.map((action) => action.type.name).toList(),
        (raw['actions']! as List)
            .map((action) => (action! as Map)['type'])
            .toList(),
        reason: 'entry[$index].actions',
      );
      expect(
        entry.presentation.variant.name,
        (raw['presentation']! as Map)['variant'],
        reason: 'entry[$index].presentation.variant',
      );
      expect(
        entry.presentation.title,
        (raw['presentation']! as Map)['title'],
        reason: 'entry[$index].presentation.title',
      );
      expect(
        entry.payload,
        isA<OpportunityEntryPayload>(),
        reason: 'entry[$index].payload',
      );
      expect(
        (entry.payload as OpportunityEntryPayload).sessionId,
        (raw['payload']! as Map)['sessionId'],
        reason: 'entry[$index].payload.sessionId',
      );
      expect(
        entry.provenance
            .map((item) => (item.sourceId, item.observedAt))
            .toList(),
        (raw['provenance']! as List).map((item) {
          final provenance = item! as Map;
          return (
            provenance['sourceId'] as String,
            DateTime.parse(provenance['observedAt']! as String),
          );
        }).toList(),
        reason: 'entry[$index].provenance',
      );
      expect(
        entry.dedupeKey,
        raw['dedupeKey'],
        reason: 'entry[$index].dedupeKey',
      );
      expect(
        entry.suppressionKeys,
        (raw['suppressionKeys']! as List).cast<String>().toSet(),
        reason: 'entry[$index].suppressionKeys',
      );
      expect(
        entry.contentFingerprint,
        raw['contentFingerprint'],
        reason: 'entry[$index].contentFingerprint',
      );
    }
  });

  test('上游多一个字段就会被整个响应拒收，所以契约必须同步演进', () async {
    final widened = Map.of(golden)..['unexpectedFutureField'] = 1;

    await expectLater(parse(widened), throwsA(isA<RemoteContextFailure>()));
  });

  test('客户端开口策略与共享契约数值一致', () {
    expect(entryBaseSurfaces.map((surface) => surface.name),
        (policy['baseSurfaces'] as List).cast<String>());
    expect(
      entrySafetySurfaces.difference(entryBaseSurfaces).map((s) => s.name),
      (policy['safetyExtraSurfaces'] as List).cast<String>(),
    );
    expect(
      entryNotificationLeadLimit.inSeconds,
      policy['interruptLeadLimitSeconds'],
      reason: '两小时提前量在三种语言里各写了一遍，只能靠这里对齐',
    );
  });

  test('presentation variant 枚举与共享契约一致', () {
    // `nextWindow` 只由本地窗口解析器产生，服务端从不发送，但它仍必须出现在
    // 服务端的枚举里：客户端按闭集解析，集合不一致会让合法条目被整份拒收。
    expect(
      EntryPresentationVariant.values.map((variant) => variant.name),
      (policy['entryPresentationVariants'] as List).cast<String>(),
    );
  });
}
