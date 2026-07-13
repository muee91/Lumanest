import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/infrastructure/amap_driving_route_repository.dart';

void main() {
  test('plans through the NAS broker and parses route details', () async {
    final transport = _FakeRouteTransport({
      'status': '1',
      'route': {
        'paths': [
          {
            'distance': '5685',
            'duration': '1260',
            'tolls': '10',
            'steps': [
              {
                'instruction': '沿道路向东行驶',
                'polyline': '121.4782,31.2284;121.4900,31.2350',
              },
            ],
          },
        ],
      },
    });
    final repository = AmapDrivingRouteRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: transport,
    );

    final route = await repository.plan(
      DrivingRouteRequest(
        origin: const GeoPoint(latitude: 31.2304, longitude: 121.4737),
        destination: const GeoPoint(
          latitude: 31.2397,
          longitude: 121.4998,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        destinationName: '测试机位',
      ),
    );

    expect(transport.url, 'https://broker.example.com/v1/amap/driving');
    expect(transport.query['origin'], isNot('121.4737,31.2304'));
    expect(transport.query['destination'], '121.4998,31.2397');
    expect(route.destinationName, '测试机位');
    expect(route.distanceMeters, 5685);
    expect(route.durationSeconds, 1260);
    expect(route.tollsYuan, 10);
    expect(route.instructions.single, '沿道路向东行驶');
    expect(route.polyline, hasLength(2));
    expect(route.polyline.first.coordinateSystem, CoordinateSystem.gcj02);
  });

  test('walking mode uses the walking broker endpoint', () async {
    final transport = _FakeRouteTransport({
      'status': '1',
      'route': {
        'paths': [
          {
            'distance': '1800',
            'duration': '1500',
            'steps': [
              {
                'instruction': '沿步道向北步行',
                'polyline': '121.47,31.23;121.48,31.24',
              },
            ],
          },
        ],
      },
    });
    final repository = AmapDrivingRouteRepository(
      brokerBaseUrl: 'https://broker.example.com',
      serviceToken: 'service-token',
      transport: transport,
    );

    final route = await repository.plan(
      DrivingRouteRequest(
        origin: const GeoPoint(latitude: 31.23, longitude: 121.47),
        destination: const GeoPoint(latitude: 31.24, longitude: 121.48),
        destinationName: '徒步机位',
        travelMode: RouteTravelMode.walking,
      ),
    );

    expect(transport.url, 'https://broker.example.com/v1/amap/walking');
    expect(route.travelMode, RouteTravelMode.walking);
    expect(route.tollsYuan, 0);
  });
}

class _FakeRouteTransport implements AmapRouteTransport {
  _FakeRouteTransport(this.response);

  final Map<String, Object?> response;
  late String url;
  late Map<String, String> query;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    this.url = url;
    this.query = query;
    return response;
  }
}
