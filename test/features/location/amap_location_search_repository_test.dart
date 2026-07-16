import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/amap_location_search_repository.dart';

void main() {
  test(
    'searches the NAS broker and keeps returned AMap coordinates as GCJ-02',
    () async {
      final transport = _FakeTransport({
        'status': '1',
        'pois': [
          {
            'id': 'west-lake',
            'name': '西湖风景名胜区',
            'location': '120.1320,30.2310',
            'address': '杭州市西湖区',
          },
        ],
      });
      final repository = AmapLocationSearchRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'service-token',
        transport: transport,
      );

      final results = await repository.search('西湖');

      expect(transport.url, 'https://broker.example.com/v1/amap/search');
      expect(transport.query['keywords'], '西湖');
      expect(transport.headers['Authorization'], 'Bearer service-token');
      expect(results.single.point.coordinateSystem, CoordinateSystem.gcj02);
      expect(results.single.name, '西湖风景名胜区');
    },
  );

  test('merges nearby and global matches with distance tiers', () async {
    final transport = _FakeTransport(
      const {'status': '1', 'pois': <Object>[]},
      responses: {
        '/v1/amap/nearby': {
          'status': '1',
          'pois': [
            {'id': 'local', 'name': '附近西湖', 'location': '120.1605,30.2505'},
          ],
        },
        '/v1/amap/search': {
          'status': '1',
          'pois': [
            {'id': 'far', 'name': '北京西湖', 'location': '116.397,39.908'},
            {'id': 'regional', 'name': '区域西湖', 'location': '121.470,31.230'},
            {
              'id': 'global-local',
              'name': '本地西湖公园',
              'location': '120.1700,30.2500',
            },
          ],
        },
      },
    );
    final repository = AmapLocationSearchRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: transport,
    );

    final results = await repository.search(
      '西湖',
      center: const GeoPoint(
        latitude: 30.25,
        longitude: 120.16,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
    );

    expect(results.map((result) => result.id), [
      'local',
      'global-local',
      'regional',
      'far',
    ]);
    expect(results.first.distanceMeters, lessThan(100));
    expect(
      transport.calls.map((call) => Uri.parse(call.url).path),
      containsAll(['/v1/amap/nearby', '/v1/amap/search']),
    );
    final nearbyCall = transport.calls.singleWhere(
      (call) => Uri.parse(call.url).path == '/v1/amap/nearby',
    );
    expect(nearbyCall.query['radius'], '50000');
  });

  test('keeps global search usable when nearby lookup fails', () async {
    final transport = _FakeTransport(
      const {'status': '1', 'pois': <Object>[]},
      responses: {
        '/v1/amap/search': {
          'status': '1',
          'pois': [
            {
              'id': 'global-result',
              'name': '异地目标',
              'location': '116.397,39.908',
            },
          ],
        },
      },
      failures: const {'/v1/amap/nearby': LocationSearchFailureKind.network},
    );
    final repository = AmapLocationSearchRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: transport,
    );

    final results = await repository.search(
      '异地目标',
      center: const GeoPoint(latitude: 30.25, longitude: 120.16),
    );

    expect(results.single.id, 'global-result');
    expect(results.single.distanceMeters, greaterThan(300000));
  });
}

class _FakeTransport implements LocationSearchTransport {
  _FakeTransport(
    this.response, {
    this.responses = const {},
    this.failures = const {},
  });

  final Map<String, Object?> response;
  final Map<String, Map<String, Object?>> responses;
  final Map<String, LocationSearchFailureKind> failures;
  final List<_TransportCall> calls = [];
  late String url;
  late Map<String, String> query;
  late Map<String, String> headers;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    this.url = url;
    this.query = query;
    this.headers = headers;
    calls.add(_TransportCall(url, query));
    final path = Uri.parse(url).path;
    if (failures[path] case final failure?) {
      throw LocationSearchFailure(failure);
    }
    return responses[path] ?? response;
  }
}

class _TransportCall {
  const _TransportCall(this.url, this.query);

  final String url;
  final Map<String, String> query;
}
