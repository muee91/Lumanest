import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/infrastructure/context/data_broker_context_repository.dart';

void main() {
  test(
    'target session uses only the reviewed public target coordinate',
    () async {
      final transport = _FakeTransport()
        ..mutateResponse = (response) {
          final session = _shootingSessionBody();
          session['targetCandidates'] = [_shootingTargetBody()];
          _facts(response)['shootingSessions'] = [session];
        };
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
      final target = ShootingTarget(
        id: 'target_0123456789abcdef01234567',
        name: '东岸审核湖岸',
        coordinate: const GeoPoint(latitude: 30.251, longitude: 120.151),
        supportedSessions: const [ShootingSessionKind.waterEvening],
        viewBearingDegrees: 286,
        bearingToleranceDegrees: 25,
        accessModes: const [ShootingTravelMode.driving],
        leadTimeMinutes: 12,
        arrivalRadiusMeters: 100,
        shorelineSide: ShootingShorelineSide.east,
        reviewedAt: DateTime.utc(2026, 7, 1),
        reviewReference: Uri.parse('https://review.example/targets/east-bank'),
        sourceAttribution: '审核目录',
        sourceLicense: 'CC-BY-4.0',
        sourceUrl: Uri.parse('https://source.example/lakes/east-bank'),
      );

      final session = await repository.fetchForTarget(
        target: target,
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

      expect(transport.uri.path, '/v1/context/target-session');
      expect(transport.body.keys, {
        'contractVersion',
        'targetId',
        'targetCoordinate',
        'observedAt',
        'locale',
      });
      expect(transport.body.containsKey('userCoordinate'), isFalse);
      expect(transport.body.containsKey('deviceId'), isFalse);
      expect((transport.body['targetCoordinate'] as Map)['latitude'], 30.251);
      expect(session?.kind, ShootingSessionKind.waterEvening);
      expect(session?.conditionBand, ShootingConditionBand.good);
      expect(session?.recommendedCapabilities, {EquipmentCapability.tripod});
      expect(
        session?.targetCandidates.single.shorelineSide,
        ShootingShorelineSide.east,
      );
      expect(session?.targetCandidates.single.sourceLicense, 'CC-BY-4.0');
      expect(session?.targetCandidates.single.reviewReference.scheme, 'https');
    },
  );

  test(
    'anonymous feedback contains no identity, coordinate or media fields',
    () async {
      final transport = _FakeTransport()..fixedResponse = {'accepted': true};
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        transport: transport,
      );
      final session = ContextFixtures.waterEveningSession(
        observedAt: DateTime.utc(2026, 7, 14, 2),
      );

      await repository.upload(
        session: session,
        outcome: ShootingSessionOutcome.conditionsDidNotAppear,
        reasons: const {
          ShootingSessionOutcomeReason.wind,
          ShootingSessionOutcomeReason.cloud,
        },
      );

      expect(transport.uri.path, '/v1/context/shooting-feedback');
      expect(transport.body.keys, {
        'contractVersion',
        'ruleVersion',
        'conditionBand',
        'factors',
        'outcome',
        'reasons',
        'targetId',
      });
      expect(transport.body['targetId'], isNull);
      expect(transport.body['contractVersion'], 2);
      expect(transport.body['conditionBand'], 'good');
      expect(transport.body.toString(), isNot(contains('coordinate')));
      expect(transport.body.toString(), isNot(contains('device')));
      expect(transport.body.toString(), isNot(contains('photo')));
      expect(transport.body.toString(), isNot(contains('exif')));
    },
  );

  test(
    'debug feedback carries only the ephemeral simulation headers',
    () async {
      final transport = _FakeTransport()..fixedResponse = {'accepted': true};
      final repository = DataBrokerContextRepository(
        brokerBaseUrl: 'https://broker.example',
        serviceToken: 'service-token',
        debugSimulationSession: 'debugsession2345678',
        transport: transport,
      );

      await repository.upload(
        session: ContextFixtures.waterEveningSession(
          observedAt: DateTime.utc(2026, 7, 14, 2),
        ),
        outcome: ShootingSessionOutcome.captured,
        reasons: const {},
      );

      expect(transport.headers, {
        'Authorization': 'Bearer service-token',
        'X-LumaNest-Debug-Session': 'debugsession2345678',
        'X-LumaNest-Debug-Contract': '5',
      });
      expect(transport.body.toString(), isNot(contains('debugsession2345678')));
    },
  );

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
    expect(result.allowedActions, [ContextAction.openExplore]);
    expect(result.temperatureCelsius, 26);
    expect(result.windSpeedMetersPerSecond, 2);
    expect(result.airQualityIndex, 42);
    expect(result.airQualityCategory, '优');
    expect(result.airQualityStale, isFalse);
    expect(result.solarAzimuthDegrees, 280);
    expect(result.entries, isEmpty);
    expect(result.serverManifest, isNull);
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
      expect(result.serverManifest, isNull);
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
}

LocationReading _location() => LocationReading(
  point: const GeoPoint(latitude: 30.25, longitude: 120.15),
  recordedAt: DateTime.utc(2026, 7, 14, 2),
  accuracyMeters: 8,
);

Map<String, Object?> _shootingSessionBody() => {
  'id': 'session_0123456789abcdef01234567',
  'kind': 'waterEvening',
  'title': '湖岸晚间窗口',
  'startAt': '2026-07-14T10:10:00+08:00',
  'endAt': '2026-07-14T11:10:00+08:00',
  'primaryPhase': 'reflection',
  'conditionBand': 'good',
  'confidenceBand': 'high',
  'trend': 'improving',
  'phases': [
    {
      'kind': 'reflection',
      'startAt': '2026-07-14T10:20:00+08:00',
      'peakAt': '2026-07-14T10:35:00+08:00',
      'endAt': '2026-07-14T10:50:00+08:00',
      'conditionBand': 'good',
      'directionDegrees': 286,
    },
  ],
  'factors': [
    {
      'id': 'wind',
      'effect': 'supporting',
      'label': '风速',
      'value': '1.8m/s',
      'sourceAt': '2026-07-14T10:00:00+08:00',
    },
  ],
  'trendSamples': [
    {
      'at': '2026-07-14T10:10:00+08:00',
      'conditionIndex': 60,
      'cloudCoverPercent': 60,
      'windSpeedMps': 3,
      'precipitationMm': 0,
    },
    {
      'at': '2026-07-14T10:50:00+08:00',
      'conditionIndex': 80,
      'cloudCoverPercent': 50,
      'windSpeedMps': 1.8,
      'precipitationMm': 0,
    },
  ],
  'targetCandidates': [],
  'recommendedCapabilities': ['tripod'],
  'ruleVersion': 'water-evening.1',
  'expiresAt': '2026-07-14T10:15:00+08:00',
};

Map<String, Object?> _shootingTargetBody() => {
  'id': 'target_0123456789abcdef01234567',
  'name': '东岸审核湖岸',
  'kind': 'lakeshore',
  'coordinate': {'latitude': 30.251, 'longitude': 120.151, 'system': 'wgs84'},
  'supportedSessions': ['waterMorning', 'waterEvening'],
  'viewBearingDegrees': 286,
  'bearingToleranceDegrees': 25,
  'accessModes': ['driving'],
  'leadTimeMinutes': 12,
  'arrivalRadiusMeters': 100,
  'shorelineSide': 'east',
  'reviewedAt': '2026-07-01T00:00:00Z',
  'reviewReference': 'https://review.example/targets/east-bank',
  'sourceAttribution': '审核目录',
  'sourceLicense': 'CC-BY-4.0',
  'sourceUrl': 'https://source.example/lakes/east-bank',
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
      'sourceRevisions': {'weather': 1, 'solar': 1, 'scene': 1, 'route': 1},
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
        'solar': 'phase-boundary',
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
