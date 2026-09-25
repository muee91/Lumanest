import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
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
    expect(snapshot.entries.length, (golden['entries'] as List).length);
    expect(snapshot.entries, isNotEmpty, reason: 'golden 必须带着真实条目');
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
}
