import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_safety_detail_repository.dart';

void main() {
  test(
    'accepts bounded official safety detail for the requested context event',
    () async {
      final transport = _FakeSafetyDetailTransport();
      final repository = DataBrokerSafetyDetailRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'token',
        transport: transport,
      );

      final detail = await repository.fetch(
        contextId: 'ctx_1234567890abcdef12345678',
        eventId: 'weather-warning-abcdef123456',
      );

      expect(transport.body, {
        'contextId': 'ctx_1234567890abcdef12345678',
        'eventId': 'weather-warning-abcdef123456',
      });
      expect(detail?.title, '雷电红色预警');
      expect(detail?.guidance, ['远离制高点和水边。']);
    },
  );

  test('returns null when the short-lived detail cache has expired', () async {
    final repository = DataBrokerSafetyDetailRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: _EmptySafetyDetailTransport(),
    );

    expect(
      await repository.fetch(
        contextId: 'ctx_1234567890abcdef12345678',
        eventId: 'weather-warning-abcdef123456',
      ),
      isNull,
    );
  });

  test('rejects overlong or malformed safety detail fields', () async {
    final repository = DataBrokerSafetyDetailRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: _MalformedSafetyDetailTransport(),
    );

    await expectLater(
      repository.fetch(
        contextId: 'ctx_1234567890abcdef12345678',
        eventId: 'weather-warning-abcdef123456',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

class _FakeSafetyDetailTransport implements SafetyDetailTransport {
  Map<String, Object?>? body;

  @override
  Future<Map<String, Object?>> post(
    String _, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.body = body;
    return {
      'eventId': 'weather-warning-abcdef123456',
      'title': '雷电红色预警',
      'description': '未来两小时有雷电活动。',
      'guidance': ['远离制高点和水边。'],
      'source': '和风天气 · 官方预警',
      'severity': 'critical',
      'observedAt': '2026-07-14T01:55:00Z',
      'expiresAt': '2026-07-14T04:00:00Z',
      'contextId': 'ctx_1234567890abcdef12345678',
    };
  }
}

class _EmptySafetyDetailTransport implements SafetyDetailTransport {
  @override
  Future<Map<String, Object?>> post(
    String _, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async => const {};
}

class _MalformedSafetyDetailTransport implements SafetyDetailTransport {
  @override
  Future<Map<String, Object?>> post(
    String _, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async => {
    'eventId': body['eventId'],
    'title': '预警',
    'description': 'x' * 501,
    'guidance': const ['远离风险区域。'],
    'source': '和风天气 · 官方预警',
    'severity': 'critical',
    'observedAt': '2026-07-14T01:55:00Z',
    'expiresAt': '2026-07-14T04:00:00Z',
    'contextId': body['contextId'],
  };
}
