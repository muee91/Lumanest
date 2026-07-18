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
          'media': [
            {
              'id': '1234567890abcdef12345678',
              'kind': 'photo',
              'proxyPath': '/v1/amap/media/abcdefghijklmnop',
              'title': '湖岸观景台',
              'attribution': '高德地图',
            },
          ],
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
    expect(
      places.single.coverMedia?.url,
      'https://broker.example.com/v1/amap/media/abcdefghijklmnop',
    );
    expect(places.single.coverMedia?.attribution, '高德地图');
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
    'sunrise candidate search merges configured POI queries and deduplicates',
    () async {
      final transport = _KeywordTransport();
      final repository = AmapNearbyPlaceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'service-token',
        transport: transport,
      );

      final places = await repository.fetchNearby(
        center: const GeoPoint(
          latitude: 30,
          longitude: 120,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        category: NearbyPlaceCategory.sunriseCandidate,
        radiusMeters: 50000,
      );

      expect(
        transport.keywords,
        NearbyPlaceCategory.sunriseCandidate.searchKeywords,
      );
      expect(places.map((place) => place.id), ['shared']);
      expect(places.single.category, NearbyPlaceCategory.sunriseCandidate);
      expect(
        places.single.administrativeRelation,
        NearbyAdministrativeRelation.sameCity,
      );
    },
  );

  test(
    'waterfront search covers multiple kinds of usable waterside POI',
    () async {
      final transport = _KeywordTransport();
      final repository = AmapNearbyPlaceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'service-token',
        transport: transport,
      );

      final places = await repository.fetchNearby(
        center: const GeoPoint(
          latitude: 30,
          longitude: 120,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        category: NearbyPlaceCategory.waterfront,
      );

      expect(transport.keywords, NearbyPlaceCategory.waterfront.searchKeywords);
      expect(transport.keywords, containsAll(['湖泊', '湿地公园', '滨江公园', '堤岸']));
      expect(places, hasLength(1));
    },
  );

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

  test(
    'candidate search drops explicitly closed or non-public places',
    () async {
      final repository = AmapNearbyPlaceRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'service-token',
        transport: _CandidateTransport(),
      );

      final places = await repository.fetchNearby(
        center: const GeoPoint(
          latitude: 30,
          longitude: 120,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        category: NearbyPlaceCategory.sunriseCandidate,
        radiusMeters: 50000,
      );

      expect(places.map((place) => place.name), ['正常开放公园']);
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

class _KeywordTransport implements AmapDataTransport {
  final keywords = <String>[];

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    if (url.endsWith('/scene-evidence')) {
      return {
        'status': '1',
        'regeocode': {
          'addressComponent': {'city': '嘉兴市', 'district': '海宁市'},
        },
      };
    }
    keywords.add(query['keywords']!);
    return {
      'status': '1',
      'pois': [
        {
          'id': 'shared',
          'name': '公共候选地点',
          'location': '120.0010,30.0000',
          'pname': '浙江省',
          'cityname': '嘉兴市',
          'adname': '海盐县',
          'type': '风景名胜;风景名胜相关;旅游景点',
        },
      ],
    };
  }
}

class _CandidateTransport implements AmapDataTransport {
  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    if (url.endsWith('/scene-evidence')) {
      return {
        'status': '1',
        'regeocode': {
          'addressComponent': {'city': '嘉兴市', 'district': '海宁市'},
        },
      };
    }
    return {
      'status': '1',
      'pois': [
        {
          'id': 'closed',
          'name': '水源湿地(不对外开放)',
          'location': '120.0010,30.0000',
          'type': '风景名胜;公园广场;公园',
        },
        {
          'id': 'open',
          'name': '正常开放公园',
          'location': '120.0020,30.0000',
          'type': '风景名胜;公园广场;公园',
        },
      ],
    };
  }
}
