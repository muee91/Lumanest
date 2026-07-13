import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
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
}

class _FakeTransport implements LocationSearchTransport {
  _FakeTransport(this.response);

  final Map<String, Object?> response;
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
    return response;
  }
}
