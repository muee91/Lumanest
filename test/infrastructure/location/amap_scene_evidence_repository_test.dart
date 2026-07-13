import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/location/amap_scene_evidence_repository.dart';

void main() {
  test(
    'classifies explicit AMap semantic entities without exposing guesses',
    () async {
      final transport = _FakeTransport({
        'status': '1',
        'regeocode': {
          'addressComponent': {'township': '西湖街道'},
          'aois': [
            {'name': '西湖风景名胜区', 'type': '风景名胜;风景名胜相关;旅游景点'},
          ],
          'pois': [
            {'name': '西湖游船码头', 'type': '交通设施服务'},
          ],
        },
      });
      final repository = AmapSceneEvidenceRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'token',
        transport: transport,
      );

      final evidence = await repository.fetch(
        const GeoPoint(latitude: 30.25, longitude: 120.15),
      );

      expect(evidence.waterBody, isTrue);
      expect(evidence.mountainous, isFalse);
      expect(evidence.source, SceneEvidenceSource.amapSemanticEntities);
      expect(
        transport.lastUrl,
        'https://broker.example/v1/amap/scene-evidence',
      );
      expect(transport.lastQuery?['location'], isNot('120.15,30.25'));
    },
  );

  test(
    'recognizes mountain, desert and village only from explicit terms',
    () async {
      Future<SceneEvidence> parse(List<Map<String, String>> aois) {
        return AmapSceneEvidenceRepository(
          brokerBaseUrl: 'https://broker.example',
          serviceToken: 'token',
          transport: _FakeTransport({
            'status': '1',
            'regeocode': {
              'addressComponent': <String, Object?>{},
              'aois': aois,
              'pois': <Object?>[],
            },
          }),
        ).fetch(const GeoPoint(latitude: 30, longitude: 100));
      }

      expect(
        (await parse([
          {'name': '四姑娘山', 'type': '风景名胜'},
        ])).mountainous,
        isTrue,
      );
      expect(
        (await parse([
          {'name': '巴丹吉林沙漠', 'type': '风景名胜'},
        ])).aridLand,
        isTrue,
      );
      expect(
        (await parse([
          {'name': '古村落', 'type': '地名地址信息'},
        ])).settlement,
        isTrue,
      );
    },
  );

  test(
    'uses POI density as urban evidence only without natural evidence',
    () async {
      final pois = List.generate(
        12,
        (index) => {'name': '城市设施$index', 'type': '生活服务'},
      );
      final repository = AmapSceneEvidenceRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'token',
        transport: _FakeTransport({
          'status': '1',
          'regeocode': {
            'addressComponent': {'citycode': '021'},
            'aois': <Object?>[],
            'pois': pois,
          },
        }),
      );

      final evidence = await repository.fetch(
        const GeoPoint(latitude: 31.2, longitude: 121.4),
      );
      expect(evidence.urban, isTrue);
    },
  );
}

class _FakeTransport implements SceneEvidenceTransport {
  _FakeTransport(this.body);
  final Map<String, Object?> body;
  String? lastUrl;
  Map<String, String>? lastQuery;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    lastUrl = url;
    lastQuery = query;
    return body;
  }
}
