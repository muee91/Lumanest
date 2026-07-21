import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';

void main() {
  final model = DataBrokerAssistantModel(
    brokerBaseUrl: 'https://broker.example',
    serviceToken: 'token',
  );

  Stream<List<int>> bytes(String value) => Stream.value(utf8.encode(value));

  const done =
      'event: done\n'
      'data: {"source":"template","citedEventIds":[],"expiresAt":"2099-01-01T00:00:00Z"}\n\n';

  test('accepts exactly one terminal done event', () async {
    final events = await model
        .decodeEventStreamForTesting(
          bytes('event: delta\ndata: {"text":"本地答案"}\n\n$done'),
        )
        .toList();

    expect(events.whereType<AssistantStreamDelta>().single.text, '本地答案');
    expect(
      events.whereType<AssistantStreamDone>().single.answer.answer,
      '本地答案',
    );
  });

  test('rejects a truncated stream with no done event', () async {
    await expectLater(
      model
          .decodeEventStreamForTesting(
            bytes('event: delta\ndata: {"text":"半截答案"}\n\n'),
          )
          .toList(),
      throwsA(
        isA<AssistantFailure>().having(
          (failure) => failure.kind,
          'kind',
          AssistantFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'rejects duplicate done events without yielding either terminal event',
    () async {
      final seen = <AssistantStreamEvent>[];
      Object? failure;
      try {
        await for (final event in model.decodeEventStreamForTesting(
          bytes('event: delta\ndata: {"text":"答案"}\n\n$done$done'),
        )) {
          seen.add(event);
        }
      } on Object catch (error) {
        failure = error;
      }

      expect(seen.whereType<AssistantStreamDone>(), isEmpty);
      expect(failure, isA<AssistantFailure>());
      expect(
        (failure! as AssistantFailure).kind,
        AssistantFailureKind.invalidResponse,
      );
    },
  );

  test('accepts only bounded HTTPS web sources from done', () async {
    const sourcedDone =
        'event: done\n'
        'data: {"source":"model","citedEventIds":[],"expiresAt":"2099-01-01T00:00:00Z","sources":[{"title":"开放公告","publisher":"杭州日报","url":"https://hangzhou.example/x"}]}\n\n';
    final events = await model
        .decodeEventStreamForTesting(
          bytes('event: delta\ndata: {"text":"开放信息"}\n\n$sourcedDone'),
        )
        .toList();
    final answer = events.whereType<AssistantStreamDone>().single.answer;
    expect(answer.webSources.single.publisher, '杭州日报');
    expect(answer.webSources.single.url.scheme, 'https');

    const unsafeDone =
        'event: done\n'
        'data: {"source":"model","citedEventIds":[],"expiresAt":"2099-01-01T00:00:00Z","sources":[{"title":"开放公告","publisher":"未知","url":"http://unsafe.example/x"}]}\n\n';
    await expectLater(
      model
          .decodeEventStreamForTesting(
            bytes('event: delta\ndata: {"text":"开放信息"}\n\n$unsafeDone'),
          )
          .toList(),
      throwsA(isA<AssistantFailure>()),
    );
  });
}
