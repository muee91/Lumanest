import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/narrative/data_broker_manifest_narrative_model.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';

void main() {
  test('posts only bounded creative context to the trusted broker', () async {
    final transport = _FakeTransport({
      'summary': '湖面正在安静下来，可以等等倒影。',
      'noteLabels': {'session.water.evening': '等倒影'},
    });
    final model = DataBrokerManifestNarrativeModel(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    final candidate = await model.generate(
      ManifestNarrativeRequest(
        scene: SceneType.lake,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.clear,
        activeRoute: false,
        creativeEventIds: ['session.water.evening'],
        templateSummary: '今晚可以留意湖面倒影。',
      ),
    );

    expect(transport.url, 'https://broker.example/v1/narrative');
    expect(transport.headers, {'Authorization': 'Bearer service-token'});
    expect(transport.body, {
      'scene': 'lake',
      'dayPhase': 'sunset',
      'weather': 'clear',
      'activeRoute': false,
      'creativeEventIds': ['session.water.evening'],
      'templateSummary': '今晚可以留意湖面倒影。',
      'tone': 'balanced',
    });
    expect(transport.body, isNot(contains('location')));
    expect(transport.body, isNot(contains('photographyPreferences')));
    expect(transport.body, isNot(contains('activityPreferences')));
    expect(transport.body, isNot(contains('recommendationIntensity')));
    expect(transport.body, isNot(contains('equipmentList')));
    expect(transport.body, isNot(contains('preferenceFingerprint')));
    expect(candidate.summary, '湖面正在安静下来，可以等等倒影。');
    expect(candidate.noteLabels, {'session.water.evening': '等倒影'});
  });

  test('sends only the selected narrative tone from personalization', () async {
    final transport = _FakeTransport({
      'summary': '街巷光线正在变暖，先观察人与环境的关系再决定拍摄位置。',
      'noteLabels': {'session.city.after_rain': '看街巷'},
    });
    final model = DataBrokerManifestNarrativeModel(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await model.generate(
      ManifestNarrativeRequest(
        scene: SceneType.village,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.clear,
        activeRoute: false,
        creativeEventIds: ['session.city.after_rain'],
        templateSummary: '晨昏光线正在进入街巷。',
        tone: NarrativeTone.detailed,
      ),
    );

    expect(transport.body?['tone'], 'detailed');
    expect(transport.body, hasLength(7));
  });

  test('rejects malformed broker output for coordinator fallback', () async {
    final model = DataBrokerManifestNarrativeModel(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: _FakeTransport({
        'summary': '可以拍。',
        'noteLabels': {'session.water.evening': 42},
      }),
    );

    expect(
      () => model.generate(
        ManifestNarrativeRequest(
          scene: SceneType.lake,
          dayPhase: DayPhase.sunset,
          weather: WeatherType.clear,
          activeRoute: false,
          creativeEventIds: ['session.water.evening'],
          templateSummary: '今晚可以留意湖面倒影。',
        ),
      ),
      throwsFormatException,
    );
  });
}

class _FakeTransport implements NarrativeTransport {
  _FakeTransport(this.response);

  final Map<String, Object?> response;
  String? url;
  Map<String, String>? headers;
  Map<String, Object?>? body;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.url = url;
    this.headers = headers;
    this.body = body;
    return response;
  }
}
