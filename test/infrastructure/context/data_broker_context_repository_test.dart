import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';

void main() {
  test(
    'posts only the v2 context contract and applies validated events',
    () async {
      final transport = _FakeTransport();
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
      final result = await repository.enrich(
        base: _snapshot(),
        weather: _weather(),
        solar: _solar(),
      );

      expect(transport.uri.path, '/v1/context/snapshot');
      expect(transport.headers, {'Authorization': 'Bearer service-token'});
      expect(transport.body['contractVersion'], 2);
      expect(transport.body.containsKey('deviceId'), isFalse);
      expect((transport.body['coordinate'] as Map)['system'], 'wgs84');
      expect(result.id, 'ctx_1234567890abcdef12345678');
      expect(result.primaryScene, SceneType.lake);
      expect(result.opportunityIds, ['reflection']);
      expect(result.dataFreshness, ContextDataFreshness.fresh);
      expect(result.moonPhase, MoonPhase.waxingCrescent);
      expect(result.allowedActions, [ContextAction.openExplore]);
    },
  );
}

ContextSnapshot _snapshot() => ContextSnapshot(
  id: 'local',
  observedAt: DateTime.utc(2026, 7, 14, 2),
  expiresAt: DateTime.utc(2026, 7, 14, 2, 15),
  primaryScene: SceneType.lake,
  dayPhase: DayPhase.sunset,
  weather: WeatherType.clear,
  activeRoute: false,
  location: const GeoPoint(latitude: 30.25, longitude: 120.15),
);

WeatherObservation _weather() => WeatherObservation(
  observedAt: DateTime.utc(2026, 7, 14, 2),
  temperatureCelsius: 26,
  condition: WeatherCondition.clear,
  windSpeedMetersPerSecond: 2,
  windDirectionDegrees: 90,
  visibilityKilometers: 20,
  precipitationMillimeters: 0,
);

SolarState _solar() => SolarState(
  observedAt: DateTime.utc(2026, 7, 14, 2),
  elevationDegrees: 4,
  azimuthDegrees: 280,
  sunrise: DateTime.utc(2026, 7, 13, 21),
  sunset: DateTime.utc(2026, 7, 14, 11),
  dayPhase: DayPhase.sunset,
);

class _FakeTransport implements ContextDataTransport {
  late Uri uri;
  late Map<String, String> headers;
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return {
      'contractVersion': 2,
      'contextId': 'ctx_1234567890abcdef12345678',
      'generatedAt': '2026-07-14T02:00:00Z',
      'expiresAt': '2026-07-14T02:15:00Z',
      'scene': 'lake',
      'fingerprint': '1234567890abcdef12345678',
      'stale': false,
      'dataFreshness': {
        'context': 'fresh',
        'weather': 'fresh',
        'weatherObservedAt': '2026-07-14T02:00:00Z',
      },
      'weather': {
        'condition': 'clear',
        'temperatureCelsius': 26,
        'windSpeedMps': 2,
        'windDirectionDegrees': 90,
        'precipitationMm': 0,
        'visibilityKm': 20,
        'cloudCoverPercent': null,
        'thunder': false,
      },
      'sunMoon': {
        'dayPhase': 'sunset',
        'sunElevationDegrees': 4,
        'sunAzimuthDegrees': 280,
        'moonPhase': 'waxingCrescent',
        'moonIllumination': .2,
      },
      'route': {'mode': 'none', 'stage': 'none', 'active': false},
      'events': [
        {
          'id': 'reflection',
          'channel': 'opportunity',
          'source': 'rule',
          'observedAt': '2026-07-14T02:00:00Z',
          'expiresAt': '2026-07-14T02:15:00Z',
          'confidence': 0.82,
          'geoScope': 'point',
          'severity': 'info',
          'allowedAction': 'openExplore',
        },
      ],
      'allowedActions': ['openExplore'],
      'manifest': {
        'layoutMode': 'opportunity',
        'primaryEventId': 'reflection',
        'secondaryEventIds': [],
        'safetyEventIds': [],
      },
    };
  }
}
