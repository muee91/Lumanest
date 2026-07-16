import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_nearby_place_repository.dart';

void main() {
  test('queries the NAS broker and parses GCJ-02 places', () async {
    final transport = _FakeTransport({
      'status': '1',
      'pois': [
        {
          'id': 'poi-1',
          'name': '湖岸观景台',
          'location': '121.4801,31.2291',
          'distance': '860',
          'address': '湖岸路',
        },
      ],
    });
    final repository = AmapNearbyPlaceRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: transport,
    );

    final places = await repository.fetchNearby(
      center: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      category: NearbyPlaceCategory.viewpoint,
    );

    expect(transport.url, 'https://broker.example.com/v1/amap/nearby');
    expect(transport.query['keywords'], '观景台');
    expect(transport.query['location'], isNot('121.4737,31.2304'));
    expect(transport.headers['Authorization'], 'Bearer service-token');
    expect(places.single.name, '湖岸观景台');
    expect(places.single.distanceMeters, inInclusiveRange(0, 1000));
    expect(places.single.point.coordinateSystem, CoordinateSystem.gcj02);
  });

  test('drops malformed POIs instead of inventing coordinates', () async {
    final repository = AmapNearbyPlaceRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: _FakeTransport({
        'status': '1',
        'pois': [
          {'id': 'bad', 'name': '坏数据', 'location': 'unknown'},
        ],
      }),
    );

    final places = await repository.fetchNearby(
      center: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
      category: NearbyPlaceCategory.fuel,
    );

    expect(places, isEmpty);
  });

  test(
    'does not convert an already GCJ-02 route sample a second time',
    () async {
      final transport = _FakeTransport({'status': '1', 'pois': <Object>[]});
      final repository = AmapNearbyPlaceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'service-token',
        transport: transport,
      );

      await repository.fetchNearby(
        center: const GeoPoint(
          latitude: 31.2304,
          longitude: 121.4737,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        category: NearbyPlaceCategory.supply,
      );

      expect(transport.query['location'], '121.4737,31.2304');
    },
  );

  test('recomputes distance, sorts nearby first and drops outliers', () async {
    final repository = AmapNearbyPlaceRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: _FakeTransport({
        'status': '1',
        'pois': [
          {
            'id': 'farther',
            'name': '较远机位',
            'location': '120.0100,30.0000',
            'distance': '1',
          },
          {
            'id': 'outlier',
            'name': '省外异常点',
            'location': '121.0000,31.0000',
            'distance': '2',
          },
          {
            'id': 'near',
            'name': '最近机位',
            'location': '120.0010,30.0000',
            'distance': '99999',
          },
        ],
      }),
    );

    final places = await repository.fetchNearby(
      center: const GeoPoint(
        latitude: 30,
        longitude: 120,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
      category: NearbyPlaceCategory.viewpoint,
      radiusMeters: 5000,
    );

    expect(places.map((place) => place.id), ['near', 'farther']);
    expect(places.first.distanceMeters, lessThan(places.last.distanceMeters));
  });
}

class _FakeTransport implements AmapDataTransport {
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
