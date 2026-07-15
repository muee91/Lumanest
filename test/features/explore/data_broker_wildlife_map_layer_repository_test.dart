import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_wildlife_map_layer_repository.dart';

void main() {
  test(
    'parses reviewed polygon areas without changing WGS84 coordinates',
    () async {
      final transport = _FakeTransport(_response());
      final repository = DataBrokerWildlifeMapLayerRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      final layer = await repository.fetch(
        center: const GeoPoint(latitude: 30.25, longitude: 120.15),
      );

      expect(transport.url, 'https://broker.example/v1/wildlife/layers');
      expect(transport.query, {'location': '120.15,30.25', 'radiusKm': '20'});
      expect(transport.headers['Authorization'], 'Bearer service-token');
      expect(layer.radiusKilometers, 20);
      expect(layer.areas.single.name, '历史观察区域');
      expect(
        layer.areas.single.polygons.single.first.coordinateSystem,
        CoordinateSystem.wgs84,
      );
      expect(
        layer.areas.single.source.attribution,
        'Reviewed wildlife dataset',
      );
      expect(layer.attributions, ['Reviewed wildlife dataset']);
    },
  );

  test('rejects points, unknown fields and GCJ-02 query centers', () async {
    final point = _response();
    (point['areas']! as List).first['geometry'] = {
      'type': 'Point',
      'coordinates': [120.1, 30.1],
    };
    final unknown = _response()..['preciseLocations'] = true;

    for (final response in [point, unknown]) {
      final repository = DataBrokerWildlifeMapLayerRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: _FakeTransport(response),
      );
      await expectLater(
        repository.fetch(
          center: const GeoPoint(latitude: 30.25, longitude: 120.15),
        ),
        throwsA(isA<WildlifeMapLayerFailure>()),
      );
    }

    final repository = DataBrokerWildlifeMapLayerRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: _FakeTransport(_response()),
    );
    await expectLater(
      repository.fetch(
        center: const GeoPoint(
          latitude: 30.25,
          longitude: 120.15,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ),
      throwsA(
        isA<WildlifeMapLayerFailure>().having(
          (failure) => failure.kind,
          'kind',
          WildlifeMapLayerFailureKind.response,
        ),
      ),
    );
  });
}

Map<String, Object?> _response() => {
  'contractVersion': 1,
  'generatedAt': '2026-07-16T02:00:00Z',
  'radiusKm': 20,
  'areas': [
    {
      'id': List.filled(64, 'a').join(),
      'name': '历史观察区域',
      'geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [120.0, 30.0],
            [120.2, 30.0],
            [120.2, 30.2],
            [120.0, 30.0],
          ],
        ],
      },
      'source': {
        'attribution': 'Reviewed wildlife dataset',
        'version': '2026.07',
        'updatedAt': '2026-07-16T00:00:00Z',
      },
    },
  ],
};

class _FakeTransport implements WildlifeMapLayerTransport {
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
