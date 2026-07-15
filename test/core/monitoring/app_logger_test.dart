import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';

void main() {
  test('emits only approved scalar fields as an immutable UTC record', () {
    final records = <LogRecord>[];
    final logger = AppLogger(
      sink: records.add,
      now: () => DateTime.parse('2026-07-15T12:00:00+08:00'),
    );

    logger.info(
      LogCategory.contextSnapshot,
      'context.refresh_completed',
      data: {
        LogDataKey.status: 'ok',
        LogDataKey.scene: 'mountain',
        LogDataKey.eventCount: 2,
        'latitude': 30.123456,
        'longitude': 120.654321,
        'apiKey': 'secret-key',
        'prompt': 'raw model prompt',
      },
    );

    final record = records.single;
    expect(record.timestamp, DateTime.utc(2026, 7, 15, 4));
    expect(record.data, {
      LogDataKey.status: 'ok',
      LogDataKey.scene: 'mountain',
      LogDataKey.eventCount: 2,
    });
    expect(
      () => record.data![LogDataKey.status] = 'changed',
      throwsUnsupportedError,
    );
    expect(record.toString(), isNot(contains('30.123456')));
    expect(record.toString(), isNot(contains('120.654321')));
    expect(record.toString(), isNot(contains('secret-key')));
    expect(record.toString(), isNot(contains('raw model prompt')));
  });

  test('invalid event and values cannot reach the sink', () {
    final records = <LogRecord>[];
    final logger = AppLogger(sink: records.add);

    logger.warning(
      LogCategory.error,
      'token=event-secret',
      data: {
        LogDataKey.status: 'contains spaces and secrets',
        LogDataKey.source: {'token': 'nested-secret'},
        LogDataKey.reason: StateError('raw-error-secret'),
        LogDataKey.tone: 'simple-secret-value',
        LogDataKey.eventCount: 30.123456,
        LogDataKey.safetyCount: -1,
      },
    );

    final record = records.single;
    expect(record.category, LogCategory.error);
    expect(record.event, 'invalid_event');
    expect(record.data, isNull);
    expect(record.toString(), isNot(contains('secret')));
    expect(record.toString(), isNot(contains('30.123456')));
  });

  test('disabled logger emits no records', () {
    final records = <LogRecord>[];
    final logger = AppLogger(enabled: false, sink: records.add);

    logger.error(LogCategory.error, 'context.unexpected_failure');

    expect(records, isEmpty);
  });
}
