import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/active_shooting_intent.dart';

void main() {
  test('round trips the selected session and target through query values', () {
    final original = ActiveShootingIntent(
      sessionId: 'session_aaaaaaaaaaaaaaaaaaaaaaaa',
      targetId: 'target_north_ridge',
      createdAt: DateTime.utc(2026, 9, 26, 10, 30),
    );

    final restored = ActiveShootingIntent.fromQueryParameters(
      sessionId: original.sessionId,
      targetId: original.queryParameters['target'],
      createdAt: original.queryParameters['intentAt'],
    );

    expect(restored?.sessionId, original.sessionId);
    expect(restored?.targetId, original.targetId);
    expect(restored?.createdAt, original.createdAt);
  });

  test('plain session links remain legacy links without an intent', () {
    expect(
      ActiveShootingIntent.fromQueryParameters(
        sessionId: 'session_aaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isNull,
    );
  });

  test('malformed identity values are rejected', () {
    expect(
      ActiveShootingIntent.fromQueryParameters(
        sessionId: 'bad',
        targetId: 'target_north_ridge',
        createdAt: '2026-09-26T10:30:00Z',
      ),
      isNull,
    );
    expect(
      ActiveShootingIntent.fromQueryParameters(
        sessionId: 'session_aaaaaaaaaaaaaaaaaaaaaaaa',
        targetId: 'target_north_ridge',
        createdAt: 'not-a-date',
      ),
      isNull,
    );
  });
}
