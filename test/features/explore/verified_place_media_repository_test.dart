import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/infrastructure/verified_place_media_repository.dart';

class _Transport implements VerifiedPlaceMediaTransport {
  _Transport(this.body);

  final Map<String, Object?> body;
  Map<String, String>? query;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    expect(url, 'https://broker.example/v1/explore/place-media');
    expect(headers, {'Authorization': 'Bearer token'});
    this.query = query;
    return body;
  }
}

NearbyPlace _place() => const NearbyPlace(
  id: 'poi-1',
  name: '长山河生态湿地公园',
  category: NearbyPlaceCategory.sunriseCandidate,
  point: GeoPoint(
    latitude: 30.6842,
    longitude: 120.7281,
    coordinateSystem: CoordinateSystem.gcj02,
  ),
  distanceMeters: 3300,
  cityName: '嘉兴市',
);

void main() {
  test(
    'loads only broker-verified detail media after a place is selected',
    () async {
      final transport = _Transport({
        'status': 'ok',
        'media': [
          {
            'id': '0123456789abcdef01234567',
            'proxyPath': '/v1/explore/media/abcdefghijklmnop',
            'title': '长山河生态湿地公园',
            'attribution': 'Wikimedia Commons',
            'creator': 'Example',
            'license': 'CC BY-SA 4.0',
            'sourceUrl': 'https://commons.wikimedia.org/?curid=42',
            'matchBasis': 'name',
            'sourceTier': 'primary',
          },
          {
            'id': 'fedcba9876543210fedcba98',
            'proxyPath': '/v1/explore/media/ponmlkjihgfedcba',
            'title': '长山河生态湿地公园 · 湖岸',
            'attribution': '高德地图',
            'sourceUrl': 'https://www.amap.com/place/poi-1',
            'matchBasis': 'amapPoiId',
            'sourceTier': 'supplemental',
          },
        ],
      });
      final repository = VerifiedPlaceMediaRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'token',
        transport: transport,
      );

      final media = await repository.fetch(_place());

      expect(
        media.first.url,
        'https://broker.example/v1/explore/media/abcdefghijklmnop',
      );
      expect(media, hasLength(2));
      expect(media.first.attribution, 'Wikimedia Commons');
      expect(media.last.matchBasis, 'amapPoiId');
      expect(transport.query?['name'], '长山河生态湿地公园');
      expect(transport.query?['city'], '嘉兴市');
      expect(transport.query?['lat'], isNot('30.684200'));
      expect(transport.query?['poiId'], 'poi-1');
    },
  );

  test('returns no media when the resolver cannot prove a match', () async {
    final repository = VerifiedPlaceMediaRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: _Transport({'status': 'unavailable', 'media': null}),
    );

    expect(await repository.fetch(_place()), isEmpty);
  });

  test('rejects a direct third-party image URL from the response', () async {
    final repository = VerifiedPlaceMediaRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'token',
      transport: _Transport({
        'status': 'ok',
        'media': [
          {
            'id': '0123456789abcdef01234567',
            'proxyPath': 'https://upload.wikimedia.org/wrong.jpg',
            'attribution': 'Wikimedia Commons',
            'sourceUrl': 'https://commons.wikimedia.org/?curid=42',
          },
        ],
      }),
    );

    expect(await repository.fetch(_place()), isEmpty);
  });
}
