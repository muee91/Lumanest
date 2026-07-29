import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_popular_place_repository.dart';

void main() {
  test(
    'uses the discovery API and retains only source-linked coordinates',
    () async {
      final transport = _Transport({
        'missionType': 'popularPlaces',
        'status': 'ready',
        'items': [
          {
            'id': 'source-1',
            'title': '海盐观海园',
            'coordinate': {
              'latitude': 30.5048,
              'longitude': 120.9509,
              'system': 'wgs84',
            },
            'distanceMeters': 23800,
            'address': '海盐县',
            'evidence': [
              {'publisher': '地方文旅'},
              {'publisher': '摄影资料'},
            ],
          },
        ],
      });
      final repository = DataBrokerPopularPlaceEvidenceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: transport,
        now: () => DateTime.utc(2026, 7, 18, 15),
      );

      final result = await repository.fetch(
        center: const GeoPoint(latitude: 30.52308, longitude: 120.69928),
        radiusMeters: 50000,
        focus: '嘉兴市及周边日出摄影地点',
      );

      expect(transport.url, 'https://broker.example.com/v1/explore/discover');
      expect(transport.body['missionType'], 'popularPlaces');
      expect(result.single.title, '海盐观海园');
      expect(result.single.sourceCount, 2);
    },
  );

  test(
    'pending or malformed discovery data collapses without blocking POI',
    () async {
      final repository = DataBrokerPopularPlaceEvidenceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: _Transport({
          'missionType': 'popularPlaces',
          'status': 'pending',
          'items': <Object>[],
        }),
      );

      expect(
        await repository.fetch(
          center: const GeoPoint(latitude: 30.5, longitude: 120.7),
          radiusMeters: 50000,
          focus: '日出摄影地点',
        ),
        isEmpty,
      );
    },
  );

  test(
    'marks source-linked human-interest discovery separately from POI',
    () async {
      final repository = DataBrokerPopularPlaceEvidenceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: _Transport({
          'missionType': 'popularPlaces',
          'status': 'ready',
          'items': [
            {
              'id': 'culture-1',
              'title': '康桥1924',
              'coordinate': {
                'latitude': 30.52,
                'longitude': 120.7,
                'system': 'wgs84',
              },
              'distanceMeters': 400,
              'evidence': [
                {'publisher': '地方文旅'},
              ],
            },
          ],
        }),
      );

      final results = await repository.fetch(
        center: const GeoPoint(latitude: 30.5, longitude: 120.7),
        radiusMeters: 5000,
        focus: '当前位置及周边人文街巷、传统建筑和文化空间',
      );

      expect(results.single.humanityScoped, isTrue);
    },
  );
}

class _Transport implements PopularPlaceEvidenceTransport {
  _Transport(this.response);

  final Map<String, Object?> response;
  late String url;
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    this.url = url;
    this.body = body;
    return response;
  }
}
