import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';

void main() {
  test(
    'posts the minimal v2 context contract and builds a complete snapshot',
    () async {
      final transport = _FakeTransport();
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
      final result = await repository.fetchSnapshot(
        location: _location(),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

      expect(transport.uri.path, '/v1/context/snapshot');
      expect(transport.headers, {'Authorization': 'Bearer service-token'});
      expect(transport.body['contractVersion'], 2);
      expect(transport.body.containsKey('deviceId'), isFalse);
      expect(transport.body.containsKey('weather'), isFalse);
      expect(transport.body.containsKey('evidence'), isFalse);
      expect(transport.body.containsKey('solar'), isFalse);
      expect((transport.body['coordinate'] as Map)['system'], 'wgs84');
      expect(result.id, 'ctx_1234567890abcdef12345678');
      expect(result.primaryScene, SceneType.lake);
      expect(result.opportunityIds, ['reflection']);
      expect(result.dataFreshness, ContextDataFreshness.fresh);
      expect(result.moonPhase, MoonPhase.waxingCrescent);
      expect(result.allowedActions, [ContextAction.openExplore]);
      expect(result.temperatureCelsius, 26);
      expect(result.windSpeedMetersPerSecond, 2);
      expect(result.airQualityIndex, 42);
      expect(result.airQualityCategory, '优');
      expect(result.airQualityStale, isFalse);
      expect(result.solarAzimuthDegrees, 280);
      expect(result.serverManifest, isNotNull);
      expect(result.serverManifest!.layout, ServerManifestLayout.opportunity);
      expect(result.serverManifest!.primaryEventId, 'reflection');
      expect(result.serverManifest!.secondaryEventIds, isEmpty);
      expect(result.serverManifest!.safetyEventIds, isEmpty);
    },
  );

  test('canonical request carries none/none route by default', () async {
    final transport = _FakeTransport();
    final repository = DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await repository.fetchSnapshot(
      location: _location(),
      observedAt: DateTime.utc(2026, 7, 14, 2),
    );

    expect(transport.body['route'], {'mode': 'none', 'stage': 'none'});
  });

  test('canonical request carries driving/planned route', () async {
    final transport = _FakeTransport();
    final repository = DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await repository.fetchSnapshot(
      location: _location(),
      observedAt: DateTime.utc(2026, 7, 14, 2),
      route: RouteContextState.planned(ContextRouteMode.driving),
    );

    expect(transport.body['route'], {'mode': 'driving', 'stage': 'planned'});
  });

  test('canonical request carries driving/active route', () async {
    final transport = _FakeTransport();
    final repository = DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await repository.fetchSnapshot(
      location: _location(),
      observedAt: DateTime.utc(2026, 7, 14, 2),
      route: RouteContextState.active(ContextRouteMode.driving),
    );

    expect(transport.body['route'], {'mode': 'driving', 'stage': 'active'});
  });

  test('canonical request carries hiking/paused route', () async {
    final transport = _FakeTransport();
    final repository = DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await repository.fetchSnapshot(
      location: _location(),
      observedAt: DateTime.utc(2026, 7, 14, 2),
      route: RouteContextState.paused(ContextRouteMode.hiking),
    );

    expect(transport.body['route'], {'mode': 'hiking', 'stage': 'paused'});
  });

  test(
    'parses a driving/active route response when mode, stage, and active agree',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          body['route'] = {
            'mode': 'driving',
            'stage': 'active',
            'active': true,
          };
        };
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
      final result = await repository.fetchSnapshot(
        location: _location(),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

      expect(result.routeMode, ContextRouteMode.driving);
      expect(result.routeStage, ContextRouteStage.active);
      expect(result.activeRoute, isTrue);
    },
  );

  test(
    'rejects a none/planned route even when active agrees with stage',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          body['route'] = {'mode': 'none', 'stage': 'planned', 'active': false};
        };
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      await expectLater(
        repository.fetchSnapshot(
          location: _location(),
          observedAt: DateTime.utc(2026, 7, 14, 2),
        ),
        throwsA(
          isA<RemoteContextFailure>().having(
            (failure) => failure.kind,
            'kind',
            RemoteContextFailureKind.response,
          ),
        ),
      );
    },
  );

  test(
    'rejects a driving/none route even when active agrees with stage',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          body['route'] = {'mode': 'driving', 'stage': 'none', 'active': false};
        };
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      await expectLater(
        repository.fetchSnapshot(
          location: _location(),
          observedAt: DateTime.utc(2026, 7, 14, 2),
        ),
        throwsA(
          isA<RemoteContextFailure>().having(
            (failure) => failure.kind,
            'kind',
            RemoteContextFailureKind.response,
          ),
        ),
      );
    },
  );

  test('legacy enrichment remains available for an old Broker retry', () async {
    final transport = _FakeTransport();
    final repository = DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await repository.enrich(
      base: _snapshot(),
      weather: _weather(),
      solar: _solar(),
    );

    expect(transport.body.containsKey('weather'), isTrue);
    expect(transport.body.containsKey('evidence'), isTrue);
    expect(transport.body.containsKey('solar'), isTrue);
  });

  test(
    'classifies an old Broker 400 as unsupported minimal contract',
    () async {
      final requestOptions = RequestOptions(
        path: 'https://broker.example/v1/context/snapshot',
      );
      final transport = _FakeTransport()
        ..error = DioException(
          requestOptions: requestOptions,
          response: Response<Object?>(
            requestOptions: requestOptions,
            statusCode: 400,
          ),
        );
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      await expectLater(
        repository.fetchSnapshot(
          location: _location(),
          observedAt: DateTime.utc(2026, 7, 14, 2),
        ),
        throwsA(
          isA<RemoteContextFailure>().having(
            (failure) => failure.kind,
            'kind',
            RemoteContextFailureKind.unsupportedContract,
          ),
        ),
      );
    },
  );

  test(
    'classifies Broker upstream failures separately from network loss',
    () async {
      final requestOptions = RequestOptions(
        path: 'https://broker.example/v1/context/snapshot',
      );
      final transport = _FakeTransport()
        ..error = DioException(
          requestOptions: requestOptions,
          response: Response<Object?>(
            requestOptions: requestOptions,
            statusCode: 502,
          ),
        );
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      await expectLater(
        repository.fetchSnapshot(
          location: _location(),
          observedAt: DateTime.utc(2026, 7, 14, 2),
        ),
        throwsA(
          isA<RemoteContextFailure>().having(
            (failure) => failure.kind,
            'kind',
            RemoteContextFailureKind.serviceUnavailable,
          ),
        ),
      );
    },
  );

  test('rejects non-finite values and unknown response fields', () async {
    final transport = _FakeTransport()
      ..mutateResponse = (body) {
        body['unexpected'] = true;
        (body['weather']! as Map)['windSpeedMps'] = double.nan;
      };
    final repository = DataBrokerContextRepository(
      brokerBaseUrl: 'https://broker.example',
      serviceToken: 'service-token',
      transport: transport,
    );

    await expectLater(
      repository.fetchSnapshot(
        location: _location(),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      ),
      throwsA(
        isA<RemoteContextFailure>().having(
          (failure) => failure.kind,
          'kind',
          RemoteContextFailureKind.response,
        ),
      ),
    );
  });

  test(
    'Broker returns structured official wildlifeSafety event: it enters both '
    'safetyEventIds and wildlifeEventIds, and allowedAction is retained',
    () async {
      final transport = _FakeTransport()..mutateResponse = _withWildlifeSafety;
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
      final result = await repository.fetchSnapshot(
        location: _location(),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

      final wildlifeEvent = result.events.firstWhere(
        (event) => event.channel == ContextEventChannel.wildlifeSafety,
      );
      expect(result.safetyEventIds, contains(wildlifeEvent.id));
      expect(result.wildlifeEventIds, contains(wildlifeEvent.id));
      expect(wildlifeEvent.allowedAction, ContextAction.openSafety);
    },
  );

  test(
    'remote wildlifeOpportunity is accepted as a creative manifest event',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          body['events'] = [
            {
              'id': 'regional-wildlife',
              'channel': 'wildlifeOpportunity',
              'source': 'wildlifeHistorical',
              'observedAt': '2026-07-14T02:00:00Z',
              'expiresAt': '2026-07-14T02:15:00Z',
              'confidence': 0.5,
              'geoScope': 'regional',
              'severity': 'info',
              'allowedAction': 'openExplore',
            },
          ];
          body['manifest'] = {
            'layoutMode': 'opportunity',
            'primaryEventId': 'regional-wildlife',
            'secondaryEventIds': <String>[],
            'safetyEventIds': <String>[],
          };
        };
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      final result = await repository.fetchSnapshot(
        location: _location(),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

      expect(result.opportunityIds, ['regional-wildlife']);
      expect(result.wildlifeEventIds, ['regional-wildlife']);
      expect(result.serverManifest!.primaryEventId, 'regional-wildlife');
    },
  );

  test(
    'remote astronomy event preserves title and HTTPS authority action',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          body['events'] = [
            {
              'id': 'astronomy-123456789abc',
              'channel': 'opportunity',
              'source': 'astronomyCatalog',
              'observedAt': '2026-07-14T01:00:00Z',
              'expiresAt': '2026-07-14T04:00:00Z',
              'confidence': 1.0,
              'geoScope': 'regional',
              'severity': 'info',
              'allowedAction': 'openAuthority',
              'title': '英仙座流星雨极大期',
              'sourceUrl': 'https://science.nasa.gov/meteor-showers/',
            },
          ];
          body['allowedActions'] = ['openAuthority'];
          body['manifest'] = {
            'layoutMode': 'opportunity',
            'primaryEventId': 'astronomy-123456789abc',
            'secondaryEventIds': <String>[],
            'safetyEventIds': <String>[],
          };
        };
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );

      final result = await repository.fetchSnapshot(
        location: _location(),
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );
      final event = result.events.single;

      expect(event.title, '英仙座流星雨极大期');
      expect(event.source, ContextEventSource.astronomyCatalog);
      expect(event.allowedAction, ContextAction.openAuthority);
      expect(event.sourceUri?.scheme, 'https');
      expect(result.allowedActions, [ContextAction.openAuthority]);
    },
  );

  group('server manifest', () {
    DataBrokerContextRepository repositoryWithManifest({
      required void Function(Map<String, Object?> body) mutate,
    }) {
      final transport = _FakeTransport()..mutateResponse = mutate;
      return DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
    }

    Future<void> expectRejects(DataBrokerContextRepository repository) async {
      await expectLater(
        repository.fetchSnapshot(
          location: _location(),
          observedAt: DateTime.utc(2026, 7, 14, 2),
        ),
        throwsA(
          isA<RemoteContextFailure>().having(
            (failure) => failure.kind,
            'kind',
            RemoteContextFailureKind.response,
          ),
        ),
      );
    }

    test(
      'parses a complete manifest with primary, secondary, and safety',
      () async {
        final repository = repositoryWithManifest(mutate: _withRichManifest);
        final result = await repository.fetchSnapshot(
          location: _location(),
          observedAt: DateTime.utc(2026, 7, 14, 2),
        );

        final manifest = result.serverManifest!;
        expect(manifest.layout, ServerManifestLayout.opportunity);
        expect(manifest.primaryEventId, 'reflection');
        expect(manifest.secondaryEventIds, ['golden-hour', 'stillness']);
        expect(manifest.safetyEventIds, ['storm-alert']);
      },
    );

    test('rejects when primaryEventId does not exist', () async {
      final repository = repositoryWithManifest(
        mutate: (body) {
          _withRichManifest(body);
          (body['manifest']! as Map)['primaryEventId'] = 'missing';
        },
      );
      await expectRejects(repository);
    });

    test(
      'rejects when primaryEventId references a non-opportunity channel',
      () async {
        final repository = repositoryWithManifest(
          mutate: (body) {
            _withRichManifest(body);
            (body['manifest']! as Map)['primaryEventId'] = 'storm-alert';
          },
        );
        await expectRejects(repository);
      },
    );

    test(
      'rejects when a secondaryEventId references a non-opportunity channel',
      () async {
        final repository = repositoryWithManifest(
          mutate: (body) {
            _withRichManifest(body);
            (body['manifest']! as Map)['secondaryEventIds'] = ['storm-alert'];
          },
        );
        await expectRejects(repository);
      },
    );

    test('rejects when secondaryEventIds contains duplicates', () async {
      final repository = repositoryWithManifest(
        mutate: (body) {
          _withRichManifest(body);
          (body['manifest']! as Map)['secondaryEventIds'] = [
            'golden-hour',
            'golden-hour',
          ];
        },
      );
      await expectRejects(repository);
    });

    test('rejects when a safetyEventId does not exist', () async {
      final repository = repositoryWithManifest(
        mutate: (body) {
          _withRichManifest(body);
          (body['manifest']! as Map)['safetyEventIds'] = ['missing'];
        },
      );
      await expectRejects(repository);
    });

    test(
      'rejects when a safetyEventId references a non-safety channel',
      () async {
        final repository = repositoryWithManifest(
          mutate: (body) {
            _withRichManifest(body);
            (body['manifest']! as Map)['safetyEventIds'] = ['reflection'];
          },
        );
        await expectRejects(repository);
      },
    );

    test('rejects when safetyEventIds contains duplicates', () async {
      final repository = repositoryWithManifest(
        mutate: (body) {
          _withRichManifest(body);
          (body['manifest']! as Map)['safetyEventIds'] = [
            'storm-alert',
            'storm-alert',
          ];
        },
      );
      await expectRejects(repository);
    });

    test('rejects an unknown layoutMode', () async {
      final repository = repositoryWithManifest(
        mutate: (body) {
          _withRichManifest(body);
          (body['manifest']! as Map)['layoutMode'] = 'creative';
        },
      );
      await expectRejects(repository);
    });
  });
}

LocationReading _location() => LocationReading(
  point: const GeoPoint(latitude: 30.25, longitude: 120.15),
  recordedAt: DateTime.utc(2026, 7, 14, 2),
  accuracyMeters: 8,
);

void _withRichManifest(Map<String, Object?> body) {
  body['events'] = [
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
    {
      'id': 'golden-hour',
      'channel': 'opportunity',
      'source': 'solar',
      'observedAt': '2026-07-14T02:00:00Z',
      'expiresAt': '2026-07-14T02:15:00Z',
      'confidence': 0.7,
      'geoScope': 'point',
      'severity': 'info',
      'allowedAction': 'openExplore',
    },
    {
      'id': 'stillness',
      'channel': 'opportunity',
      'source': 'rule',
      'observedAt': '2026-07-14T02:00:00Z',
      'expiresAt': '2026-07-14T02:15:00Z',
      'confidence': 0.6,
      'geoScope': 'point',
      'severity': 'info',
      'allowedAction': 'openExplore',
    },
    {
      'id': 'storm-alert',
      'channel': 'safety',
      'source': 'weather',
      'observedAt': '2026-07-14T02:00:00Z',
      'expiresAt': '2026-07-14T02:15:00Z',
      'confidence': 0.9,
      'geoScope': 'regional',
      'severity': 'warning',
      'allowedAction': 'openExplore',
    },
  ];
  body['manifest'] = {
    'layoutMode': 'opportunity',
    'primaryEventId': 'reflection',
    'secondaryEventIds': ['golden-hour', 'stillness'],
    'safetyEventIds': ['storm-alert'],
  };
}

void _withWildlifeSafety(Map<String, Object?> body) {
  body['events'] = [
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
    {
      'id': 'bear-risk',
      'channel': 'wildlifeSafety',
      'source': 'official',
      'observedAt': '2026-07-14T02:00:00Z',
      'expiresAt': '2026-07-14T02:15:00Z',
      'confidence': 0.88,
      'geoScope': 'regional',
      'severity': 'warning',
      'allowedAction': 'openSafety',
    },
  ];
  body['manifest'] = {
    'layoutMode': 'safety',
    'primaryEventId': 'reflection',
    'secondaryEventIds': <String>[],
    'safetyEventIds': ['bear-risk'],
  };
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
  Object? error;
  void Function(Map<String, Object?> body)? mutateResponse;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    if (error case final failure?) throw failure;
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    final response = <String, Object?>{
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
        'airQualityIndex': 42,
        'airQualityCategory': '优',
        'primaryPollutant': null,
        'airQualityObservedAt': '2026-07-14T02:00:00Z',
        'airQualityStale': false,
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
    mutateResponse?.call(response);
    return response;
  }
}
