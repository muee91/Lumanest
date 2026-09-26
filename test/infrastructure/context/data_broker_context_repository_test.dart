import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';

void main() {
  test('uses only the strict V5 request and response contract', () async {
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
    expect(transport.body['contractVersion'], 5);
    expect(transport.body.containsKey('deviceId'), isFalse);
    expect(transport.body.containsKey('weather'), isFalse);
    expect(transport.body.containsKey('evidence'), isFalse);
    expect(transport.body.containsKey('solar'), isFalse);
    expect((transport.body['coordinate'] as Map)['system'], 'wgs84');
    expect(result.id, 'ctx_1234567890abcdef12345678');
    expect(result.primaryScene, SceneType.lake);
    expect(result.opportunityIds, ['session.water.evening']);
    expect(result.dataFreshness, ContextDataFreshness.fresh);
    expect(result.moonPhase, MoonPhase.waxingCrescent);
    expect(
      result.astronomyGeometry?.status,
      AstronomyGeometryStatus.geometryOnly,
    );
    expect(
      result.astronomyGeometry?.moonriseAt,
      DateTime.utc(2026, 7, 14, 10, 30),
    );
    expect(
      result.astronomyGeometry?.galacticCenterWindow?.peakAltitudeDegrees,
      32,
    );
    expect(result.allowedActions, [ContextAction.openExplore]);
    expect(result.temperatureCelsius, 26);
    expect(result.windSpeedMetersPerSecond, 2);
    expect(result.airQualityIndex, 42);
    expect(result.airQualityCategory, '优');
    expect(result.airQualityStale, isFalse);
    expect(result.solarAzimuthDegrees, 280);
    expect(result.entries, isEmpty);
  });

  test(
    'parses the composite scene without letting activity replace it',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (response) {
          _facts(response)['shootingSessions'] = <Object?>[];
          _environment(response)['sceneContext'] = {
            'primaryScene': 'inlandWater',
            'facets': ['lake', 'reflectiveSurface'],
            'activity': 'driving',
            'scores': {'inlandWater': 55},
            'reviewedOverride': false,
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

      expect(
        result.resolvedSceneContext.primaryScene,
        PrimaryScene.inlandWater,
      );
      expect(result.resolvedSceneContext.activity, ActivityState.driving);
      expect(result.resolvedSceneContext.facets, {
        SceneFacet.lake,
        SceneFacet.reflectiveSurface,
      });
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

    expect(transport.body['route'], {
      'mode': 'none',
      'stage': 'none',
      'routeId': null,
      'corridorSamples': <Object?>[],
    });
  });

  test(
    'parses a live quiet response when air quality is unavailable',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          final environment = _environment(body);
          final facts = _facts(body);
          environment['scene'] = 'village';
          environment['weather'] = {
            ...(environment['weather']! as Map),
            'condition': 'unknown',
            'airQualityIndex': null,
            'airQualityCategory': null,
            'primaryPollutant': null,
            'airQualityObservedAt': null,
            'airQualityStale': true,
          };
          facts['events'] = <Object?>[];
          environment['allowedActions'] = <Object?>[];
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

      expect(result.primaryScene, SceneType.village);
      expect(result.weather, WeatherType.unknown);
      expect(result.airQualityIndex, isNull);
      expect(result.airQualityStale, isTrue);
      expect(result.events, isEmpty);
    },
  );

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

    expect(transport.body['route'], {
      'mode': 'driving',
      'stage': 'planned',
      'routeId': null,
      'corridorSamples': <Object?>[],
    });
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

    expect(transport.body['route'], {
      'mode': 'driving',
      'stage': 'active',
      'routeId': null,
      'corridorSamples': <Object?>[],
    });
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

    expect(transport.body['route'], {
      'mode': 'hiking',
      'stage': 'paused',
      'routeId': null,
      'corridorSamples': <Object?>[],
    });
  });

  test(
    'parses a driving/active route response when mode, stage, and active agree',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          _environment(body)['route'] = {
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
          _environment(body)['route'] = {
            'mode': 'none',
            'stage': 'planned',
            'active': false,
          };
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
          _environment(body)['route'] = {
            'mode': 'driving',
            'stage': 'none',
            'active': false,
          };
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
        (_environment(body)['weather']! as Map)['windSpeedMps'] = double.nan;
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

  test('rejects malformed astronomy geometry before it reaches UI state', () async {
    final transport = _FakeTransport()
      ..mutateResponse = (body) {
        (_environment(body)['astronomy']! as Map)['moonAltitudeDegrees'] = 120;
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
      expect(wildlifeEvent.allowedAction, ContextAction.openSafetyDetail);
    },
  );

  test(
    'remote wildlifeOpportunity is accepted as a creative manifest event',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          _facts(body)['events'] = [
            {
              'id': 'regional-wildlife',
              'channel': 'wildlifeOpportunity',
              'source': 'wildlifeHistorical',
              'observedAt': '2026-07-14T02:00:00Z',
              'expiresAt': '2026-07-14T02:15:00Z',
              'confidence': 0.5,
              'geoScope': 'region',
              'severity': 'info',
              'allowedAction': 'openExplore',
            },
          ];
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
    },
  );

  test(
    'remote astronomy event preserves title and HTTPS authority action',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (body) {
          _facts(body)['events'] = [
            {
              'id': 'event.astro.meteor_shower',
              'channel': 'opportunity',
              'source': 'astronomyCatalog',
              'observedAt': '2026-07-14T01:00:00Z',
              'expiresAt': '2026-07-14T04:00:00Z',
              'confidence': 1.0,
              'geoScope': 'region',
              'severity': 'info',
              'allowedAction': 'openAstronomyDetail',
              'title': '英仙座流星雨极大期',
              'sourceUrl': 'https://science.nasa.gov/meteor-showers/',
            },
          ];
          _environment(body)['allowedActions'] = ['openAstronomyDetail'];
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
      expect(event.allowedAction, ContextAction.openAstronomyDetail);
      expect(event.sourceUri?.scheme, 'https');
      expect(result.allowedActions, [ContextAction.openAstronomyDetail]);
    },
  );

  test('服务端授予的通知表面原样到达客户端，未知表面被丢弃', () async {
    final transport = _FakeTransport()
      ..mutateResponse = (response) {
        response['entries'] = [
          _entryV5Body(
            surfaces: ['today', 'notification', 'widget', 'lockScreen'],
          ),
        ];
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

    expect(
      result.entries.single.allowedSurfaces,
      {EntrySurface.today, EntrySurface.notification, EntrySurface.widget},
      reason: '能否不请自来是服务端的结论，客户端不得静默丢掉这份授权',
    );
  });
}

LocationReading _location() => LocationReading(
  point: const GeoPoint(latitude: 30.25, longitude: 120.15),
  recordedAt: DateTime.utc(2026, 7, 14, 2),
  accuracyMeters: 8,
);

Map<String, Object?> _entryV5Body({required List<String> surfaces}) => {
  'id': 'entry_0123456789abcdef01234567',
  'kind': 'photographyOpportunity',
  'sourceNamespace': 'contextService.v5',
  'sourceId': 'session.water.evening',
  'revision': 1,
  'observedAt': '2026-07-14T02:00:00Z',
  'validFrom': '2026-07-14T02:05:00Z',
  'expiresAt': '2026-07-14T02:15:00Z',
  'freshness': 'fresh',
  'evidenceConfidence': 0.9,
  'basePriority': 'p1',
  'severity': 'info',
  'geoScope': 'region',
  'allowedSurfaces': surfaces,
  'actions': [
    {
      'type': 'openShootingWindow',
      'targetId': 'session.water.evening',
      'query': null,
    },
  ],
  'presentation': {
    'variant': 'shootingSession',
    'title': '湖岸晚间窗口',
    'shortLabel': '晚间窗口',
    'fallbackSummary': '风与云正在把窗口慢慢打开。',
  },
  'payload': {
    'type': 'opportunity',
    'definitionId': 'session.water.evening',
    'instanceId': 'session.water.evening',
    'sessionId': 'session.water.evening',
  },
  'provenance': [
    {
      'sourceId': 'context-service',
      'observedAt': '2026-07-14T02:00:00Z',
      'sourceUrl': null,
    },
  ],
  'dedupeKey': 'session.water.evening',
  'suppressionKeys': <String>[],
  'contentFingerprint': 'sha256:${'0' * 64}',
};

class _FakeTransport implements ContextDataTransport {
  late Uri uri;
  late Map<String, String> headers;
  late Map<String, Object?> body;
  Object? error;
  void Function(Map<String, Object?> body)? mutateResponse;
  Map<String, Object?>? fixedResponse;

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
    if (fixedResponse case final fixed?) return Map.of(fixed);
    final response = <String, Object?>{
      'contractVersion': 5,
      'contextId': 'ctx_1234567890abcdef12345678',
      'snapshotRevision': 1,
      'generatedAt': '2026-07-14T02:00:00Z',
      'expiresAt': '2026-07-14T02:15:00Z',
      'sourceRevisions': {
        'weather': 1,
        'solar': 1,
        'astronomy': 1,
        'scene': 1,
        'route': 1,
      },
      'stale': false,
      'environment': {
        'scene': 'lake',
        'sceneContext': {
          'primaryScene': 'inlandWater',
          'facets': ['lake', 'reflectiveSurface'],
          'activity': 'stationary',
          'scores': {'inlandWater': 55},
          'reviewedOverride': false,
        },
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
        'astronomy': {
          'status': 'geometryOnly',
          'astronomicalNight': false,
          'moonAltitudeDegrees': 18,
          'moonAzimuthDegrees': 110,
          'moonriseAt': '2026-07-14T10:30:00Z',
          'moonsetAt': '2026-07-14T22:10:00Z',
          'moonPhase': 'waxingCrescent',
          'moonIllumination': .2,
          'galacticCenterAltitudeDegrees': -20,
          'galacticCenterAzimuthDegrees': 240,
          'galacticCenterWindow': {
            'startAt': '2026-07-14T15:00:00Z',
            'peakAt': '2026-07-14T17:00:00Z',
            'endAt': '2026-07-14T19:00:00Z',
            'peakAltitudeDegrees': 32,
          },
        },
        'route': {'mode': 'none', 'stage': 'none', 'active': false},
        'allowedActions': ['openExplore'],
      },
      'facts': {
        'events': [
          {
            'id': 'session.water.evening',
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
        'shootingSessions': <Object?>[],
      },
      'entries': <Object?>[],
      'refreshHints': {
        'weather': 'ttl:600',
        'airQuality': 'ttl:2700',
        'solar': 'phase-boundary',
        'astronomy': 'ttl:3600',
        'opportunities': 'solar-or-weather-delta',
      },
    };
    mutateResponse?.call(response);
    return response;
  }
}

void _withWildlifeSafety(Map<String, Object?> body) {
  _facts(body)['events'] = [
    {
      'id': 'session.water.evening',
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
      'geoScope': 'region',
      'severity': 'warning',
      'allowedAction': 'openSafetyDetail',
    },
  ];
  _environment(body)['allowedActions'] = ['openExplore', 'openSafetyDetail'];
}

Map<String, Object?> _environment(Map<String, Object?> body) =>
    body['environment']! as Map<String, Object?>;

Map<String, Object?> _facts(Map<String, Object?> body) =>
    body['facts']! as Map<String, Object?>;
