import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

const _responseKeys = <String>{
  'contractVersion',
  'contextId',
  'generatedAt',
  'expiresAt',
  'scene',
  'fingerprint',
  'stale',
  'dataFreshness',
  'weather',
  'sunMoon',
  'route',
  'events',
  'allowedActions',
  'manifest',
  'shootingSessions',
  'sceneContext',
  'opportunityCatalogVersion',
};

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> keys) {
  return value.length == keys.length && value.keys.every(keys.contains);
}

bool _hasOnlyKeys(Map<Object?, Object?> value, Set<String> keys) =>
    value.keys.every(keys.contains);

bool _finiteIn(Object? value, double minimum, double maximum) {
  return value is num && value.isFinite && value >= minimum && value <= maximum;
}

Uri? _httpsUri(Object? value) {
  if (value is! String || value.length > 500) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

abstract interface class ContextDataTransport {
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

class DioContextDataTransport implements ContextDataTransport {
  DioContextDataTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final response = await _dio.postUri<Object?>(
      uri,
      data: body,
      options: Options(headers: headers),
    );
    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid context response');
    return Map<String, Object?>.from(data);
  }
}

class DataBrokerContextRepository
    implements
        RemoteContextRepository,
        ShootingTargetSessionRepository,
        ShootingFeedbackRepository {
  const DataBrokerContextRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
    this.debugSimulationSession,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final ContextDataTransport transport;
  final String? debugSimulationSession;

  @override
  Future<ContextSnapshot> fetchSnapshot({
    required LocationReading location,
    required DateTime observedAt,
    RouteContextState route = RouteContextState.none,
    RouteCorridorContext? corridor,
  }) {
    return _post(
      request: _canonicalRequest(location, observedAt, route, corridor),
      location: location.point,
    );
  }

  @override
  Future<ShootingSession?> fetchForTarget({
    required ShootingTarget target,
    required DateTime observedAt,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const RemoteContextFailure(RemoteContextFailureKind.configuration);
    }
    final uri = Uri.parse(brokerBaseUrl).resolve('/v1/context/target-session');
    try {
      final body = await transport.post(
        uri,
        headers: {'Authorization': 'Bearer $serviceToken'},
        body: {
          'contractVersion': 1,
          'targetId': target.id,
          'targetCoordinate': {
            'latitude': target.coordinate.latitude,
            'longitude': target.coordinate.longitude,
            'system': 'wgs84',
          },
          'observedAt': observedAt.toUtc().toIso8601String(),
          'locale': 'zh-CN',
        },
      );
      final snapshot = _parse(body, location: target.coordinate);
      return snapshot.shootingSessions.firstOrNull;
    } on RemoteContextFailure {
      rethrow;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      if (error.response?.statusCode case final status?
          when status == 502 || status == 503) {
        throw const RemoteContextFailure(
          RemoteContextFailureKind.serviceUnavailable,
        );
      }
      throw const RemoteContextFailure(RemoteContextFailureKind.network);
    } catch (_) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
  }

  @override
  Future<void> upload({
    required ShootingSession session,
    required ShootingSessionOutcome outcome,
    required Set<ShootingSessionOutcomeReason> reasons,
    String? targetId,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const RemoteContextFailure(RemoteContextFailureKind.configuration);
    }
    final uri = Uri.parse(
      brokerBaseUrl,
    ).resolve('/v1/context/shooting-feedback');
    try {
      final body = await transport.post(
        uri,
        headers: {'Authorization': 'Bearer $serviceToken'},
        body: {
          'contractVersion': 2,
          'ruleVersion': session.ruleVersion,
          'conditionBand': session.conditionBand.name,
          'factors': session.factors
              .map((factor) => {'id': factor.id, 'effect': factor.effect.name})
              .toList(growable: false),
          'outcome': outcome.name,
          'reasons': reasons.map((reason) => reason.name).toList()..sort(),
          'targetId': targetId,
        },
      );
      if (!_hasExactKeys(body, const {'accepted'}) ||
          body['accepted'] != true) {
        throw const RemoteContextFailure(RemoteContextFailureKind.response);
      }
    } on RemoteContextFailure {
      rethrow;
    } on DioException catch (error) {
      if (error.response?.statusCode case final status? when status == 400) {
        throw const RemoteContextFailure(RemoteContextFailureKind.response);
      }
      if (error.response?.statusCode case final status?
          when status == 502 || status == 503) {
        throw const RemoteContextFailure(
          RemoteContextFailureKind.serviceUnavailable,
        );
      }
      throw const RemoteContextFailure(RemoteContextFailureKind.network);
    } catch (_) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
  }

  Future<ContextSnapshot> _post({
    required Map<String, Object?> request,
    required GeoPoint location,
    ContextSnapshot? fallback,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const RemoteContextFailure(RemoteContextFailureKind.configuration);
    }
    final uri = Uri.parse(brokerBaseUrl).resolve('/v1/context/snapshot');
    final headers = <String, String>{'Authorization': 'Bearer $serviceToken'};
    final session = debugSimulationSession;
    if (session != null) headers['X-LumaNest-Debug-Session'] = session;
    try {
      final body = await transport.post(uri, headers: headers, body: request);
      return _parse(body, location: location, fallback: fallback);
    } on RemoteContextFailure {
      rethrow;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400) {
        throw const RemoteContextFailure(RemoteContextFailureKind.response);
      }
      if (error.response?.statusCode case final status?
          when status == 502 || status == 503) {
        throw const RemoteContextFailure(
          RemoteContextFailureKind.serviceUnavailable,
        );
      }
      throw const RemoteContextFailure(RemoteContextFailureKind.network);
    } catch (_) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
  }

  Map<String, Object?> _canonicalRequest(
    LocationReading location,
    DateTime observedAt,
    RouteContextState route,
    RouteCorridorContext? corridor,
  ) {
    return {
      'contractVersion': 4,
      'coordinate': {
        'latitude': location.point.latitude,
        'longitude': location.point.longitude,
        'system': 'wgs84',
      },
      'observedAt': observedAt.toUtc().toIso8601String(),
      'locale': 'zh-CN',
      'intent': 'photography',
      'route': {
        ...route.toRequest(),
        'routeId': route.hasRoute && corridor?.isUsable == true
            ? corridor!.routeId
            : null,
        'corridorSamples': route.hasRoute && corridor?.isUsable == true
            ? corridor!.samples
                  .map((sample) => sample.toRequest())
                  .toList(growable: false)
            : const [],
      },
    };
  }

  ContextSnapshot _parse(
    Map<String, Object?> body, {
    required GeoPoint location,
    ContextSnapshot? fallback,
  }) {
    final contractVersion = body['contractVersion'];
    if (!_hasExactKeys(body, _responseKeys) ||
        contractVersion != 4 ||
        body['contextId'] is! String ||
        body['scene'] is! String ||
        body['events'] is! List ||
        body['dataFreshness'] is! Map ||
        body['weather'] is! Map ||
        body['sunMoon'] is! Map ||
        body['route'] is! Map ||
        body['manifest'] is! Map ||
        body['allowedActions'] is! List ||
        body['shootingSessions'] is! List ||
        body['sceneContext'] is! Map ||
        body['opportunityCatalogVersion'] != 1) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final scene = SceneType.values
        .where((value) => value.name == body['scene'])
        .firstOrNull;
    final sceneContext = _sceneContext(body['sceneContext']);
    final events = (body['events'] as List).map(_event).toList(growable: false);
    final generatedAt = DateTime.tryParse('${body['generatedAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${body['expiresAt'] ?? ''}');
    final freshness = Map<String, Object?>.from(body['dataFreshness']! as Map);
    final weatherState = Map<String, Object?>.from(body['weather']! as Map);
    final sunMoon = Map<String, Object?>.from(body['sunMoon']! as Map);
    final route = Map<String, Object?>.from(body['route']! as Map);
    final manifest = Map<String, Object?>.from(body['manifest']! as Map);
    final dataFreshness = ContextDataFreshness.values
        .where((value) => value.name == freshness['context'])
        .firstOrNull;
    final weatherFreshness = ContextDataFreshness.values
        .where((value) => value.name == freshness['weather'])
        .firstOrNull;
    final weatherObservedAt = DateTime.tryParse(
      '${freshness['weatherObservedAt'] ?? ''}',
    );
    final weatherType = weatherState['condition'] == 'unknown'
        ? WeatherType.cloudy
        : WeatherType.values
              .where((value) => value.name == weatherState['condition'])
              .firstOrNull;
    final temperature = weatherState['temperatureCelsius'];
    final windSpeed = weatherState['windSpeedMps'];
    final windDirection = weatherState['windDirectionDegrees'];
    final precipitation = weatherState['precipitationMm'];
    final visibility = weatherState['visibilityKm'];
    final cloudCover = weatherState['cloudCoverPercent'];
    final thunder = weatherState['thunder'];
    final airQualityIndex = weatherState['airQualityIndex'];
    final airQualityCategory = weatherState['airQualityCategory'];
    final primaryPollutant = weatherState['primaryPollutant'];
    final airQualityObservedAt = DateTime.tryParse(
      '${weatherState['airQualityObservedAt'] ?? ''}',
    );
    final airQualityStale = weatherState['airQualityStale'];
    final sunDayPhase = DayPhase.values
        .where((value) => value.name == sunMoon['dayPhase'])
        .firstOrNull;
    final moonPhase = MoonPhase.values
        .where((value) => value.name == sunMoon['moonPhase'])
        .firstOrNull;
    final routeMode = ContextRouteMode.values
        .where((value) => value.name == route['mode'])
        .firstOrNull;
    final routeStage = ContextRouteStage.values
        .where((value) => value.name == route['stage'])
        .firstOrNull;
    final moonIllumination = sunMoon['moonIllumination'];
    final solarElevation = sunMoon['sunElevationDegrees'];
    final solarAzimuth = sunMoon['sunAzimuthDegrees'];
    final actions = (body['allowedActions']! as List)
        .map((raw) {
          if (raw is! String) {
            throw const FormatException('Invalid context action');
          }
          return ContextAction.values
              .where((value) => value.name == raw)
              .firstOrNull;
        })
        .toList(growable: false);
    final shootingSessions = _shootingSessions(
      body['shootingSessions'] as List,
    );
    if (!RegExp(r'^ctx_[a-f0-9]{24}$').hasMatch(body['contextId']! as String) ||
        body['fingerprint'] is! String ||
        !RegExp(r'^[a-f0-9]{24}$').hasMatch(body['fingerprint']! as String) ||
        !_hasExactKeys(freshness, const {
          'context',
          'weather',
          'weatherObservedAt',
        }) ||
        !_hasExactKeys(weatherState, const {
          'condition',
          'temperatureCelsius',
          'windSpeedMps',
          'windDirectionDegrees',
          'precipitationMm',
          'visibilityKm',
          'cloudCoverPercent',
          'thunder',
          'airQualityIndex',
          'airQualityCategory',
          'primaryPollutant',
          'airQualityObservedAt',
          'airQualityStale',
        }) ||
        !_hasExactKeys(sunMoon, const {
          'dayPhase',
          'sunElevationDegrees',
          'sunAzimuthDegrees',
          'moonPhase',
          'moonIllumination',
        }) ||
        !_hasExactKeys(route, const {'mode', 'stage', 'active'}) ||
        !_hasExactKeys(manifest, const {
          'layoutMode',
          'primaryEventId',
          'secondaryEventIds',
          'safetyEventIds',
        }) ||
        scene == null ||
        sceneContext == null ||
        generatedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(generatedAt) ||
        dataFreshness == null ||
        weatherFreshness == null ||
        weatherObservedAt == null ||
        weatherType == null ||
        (temperature != null && !_finiteIn(temperature, -100, 100)) ||
        !_finiteIn(windSpeed, 0, 150) ||
        (windDirection != null && !_finiteIn(windDirection, 0, 359.999)) ||
        !_finiteIn(precipitation, 0, 2000) ||
        !_finiteIn(visibility, 0, 500) ||
        (cloudCover != null && !_finiteIn(cloudCover, 0, 100)) ||
        thunder is! bool ||
        (airQualityIndex != null &&
            (airQualityIndex is! int || !_finiteIn(airQualityIndex, 0, 500))) ||
        (airQualityCategory != null &&
            (airQualityCategory is! String ||
                airQualityCategory.isEmpty ||
                airQualityCategory.runes.length > 40)) ||
        (primaryPollutant != null &&
            (primaryPollutant is! String ||
                primaryPollutant.isEmpty ||
                primaryPollutant.runes.length > 40)) ||
        airQualityStale is! bool ||
        ((airQualityIndex == null) != (airQualityObservedAt == null)) ||
        sunDayPhase == null ||
        (solarElevation != null && !_finiteIn(solarElevation, -90, 90)) ||
        (solarAzimuth != null && !_finiteIn(solarAzimuth, 0, 359.999)) ||
        moonPhase == null ||
        routeMode == null ||
        routeStage == null ||
        !_finiteIn(moonIllumination, 0, 1) ||
        route['active'] is! bool ||
        (route['active'] == true) != (routeStage == ContextRouteStage.active) ||
        (routeMode == ContextRouteMode.none) !=
            (routeStage == ContextRouteStage.none) ||
        body['stale'] is! bool ||
        !const {
          'quiet',
          'opportunity',
          'safety',
        }.contains(manifest['layoutMode']) ||
        (manifest['primaryEventId'] != null &&
            manifest['primaryEventId'] is! String) ||
        manifest['secondaryEventIds'] is! List ||
        (manifest['secondaryEventIds']! as List).length > 2 ||
        (manifest['secondaryEventIds']! as List).any(
          (value) => value is! String,
        ) ||
        manifest['safetyEventIds'] is! List ||
        (manifest['safetyEventIds']! as List).any(
          (value) => value is! String,
        ) ||
        actions.any((action) => action == null)) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final layout = ServerManifestLayout.fromServerString(
      manifest['layoutMode']! as String,
    );
    if (layout == null) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final primaryEventId = manifest['primaryEventId'] as String?;
    final secondaryEventIds = (manifest['secondaryEventIds']! as List)
        .cast<String>();
    final safetyEventIds = (manifest['safetyEventIds']! as List).cast<String>();
    final eventById = <String, ContextEvent>{
      for (final event in events) event.id: event,
    };
    if (!_manifestReferencesAreValid(
      primaryEventId: primaryEventId,
      secondaryEventIds: secondaryEventIds,
      safetyEventIds: safetyEventIds,
      eventById: eventById,
    )) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final serverManifest = ServerManifest(
      layout: layout,
      primaryEventId: primaryEventId,
      secondaryEventIds: secondaryEventIds,
      safetyEventIds: safetyEventIds,
    );
    return ContextSnapshot(
      id: body['contextId']! as String,
      observedAt: weatherObservedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      primaryScene: scene,
      sceneContext: sceneContext,
      dayPhase: sunDayPhase,
      weather: weatherType,
      activeRoute: route['active']! as bool,
      opportunityIds: events
          .where(
            (event) =>
                event.channel == ContextEventChannel.opportunity ||
                event.channel == ContextEventChannel.wildlifeOpportunity,
          )
          .map((event) => event.id)
          .toList(growable: false),
      safetyEventIds: events
          .where(
            (event) =>
                event.channel == ContextEventChannel.safety ||
                event.channel == ContextEventChannel.wildlifeSafety,
          )
          .map((event) => event.id)
          .toList(growable: false),
      wildlifeEventIds: events
          .where(
            (event) =>
                event.channel == ContextEventChannel.wildlifeOpportunity ||
                event.channel == ContextEventChannel.wildlifeSafety,
          )
          .map((event) => event.id)
          .toList(growable: false),
      events: events,
      shootingSessions:
          body['stale']! as bool ||
              dataFreshness == ContextDataFreshness.stale ||
              weatherFreshness == ContextDataFreshness.stale
          ? const []
          : shootingSessions,
      wildlifeActivity: fallback?.wildlifeActivity,
      location: location,
      temperatureCelsius: (temperature as num?)?.toDouble(),
      windSpeedMetersPerSecond: (windSpeed! as num).toDouble(),
      windDirectionDegrees: (windDirection as num?)?.toDouble(),
      visibilityKilometers: (visibility! as num).toDouble(),
      precipitationMillimeters: (precipitation! as num).toDouble(),
      cloudCoverPercent: (cloudCover as num?)?.toDouble(),
      airQualityIndex: airQualityIndex as int?,
      airQualityCategory: airQualityCategory as String?,
      primaryPollutant: primaryPollutant as String?,
      airQualityObservedAt: airQualityObservedAt?.toUtc(),
      airQualityStale: airQualityStale,
      solarElevationDegrees: (solarElevation as num?)?.toDouble(),
      solarAzimuthDegrees: (solarAzimuth as num?)?.toDouble(),
      sunrise: fallback?.sunrise,
      sunset: fallback?.sunset,
      isStale:
          body['stale']! as bool ||
          dataFreshness == ContextDataFreshness.stale ||
          weatherFreshness == ContextDataFreshness.stale,
      remoteGeneratedAt: generatedAt.toUtc(),
      dataFreshness: dataFreshness,
      moonPhase: moonPhase,
      moonIllumination: (moonIllumination! as num).toDouble(),
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: actions.cast<ContextAction>(),
      serverManifest: serverManifest,
    );
  }

  SceneContext? _sceneContext(Object? raw) {
    if (raw is! Map ||
        !_hasExactKeys(raw, const {
          'primaryScene',
          'facets',
          'activity',
          'scores',
          'reviewedOverride',
        })) {
      return null;
    }
    final primary = PrimaryScene.values
        .where((item) => item.name == raw['primaryScene'])
        .firstOrNull;
    final activity = ActivityState.values
        .where((item) => item.name == raw['activity'])
        .firstOrNull;
    final rawFacets = raw['facets'];
    final rawScores = raw['scores'];
    if (primary == null ||
        activity == null ||
        rawFacets is! List ||
        rawFacets.length > SceneFacet.values.length ||
        rawScores is! Map ||
        raw['reviewedOverride'] is! bool) {
      return null;
    }
    final facets = rawFacets
        .map((value) {
          if (value is! String) return null;
          return SceneFacet.values
              .where((item) => item.name == value)
              .firstOrNull;
        })
        .toList(growable: false);
    if (facets.any((item) => item == null) ||
        facets.whereType<SceneFacet>().toSet().length != facets.length) {
      return null;
    }
    final scores = <PrimaryScene, int>{};
    for (final entry in rawScores.entries) {
      final key = PrimaryScene.values
          .where((item) => item.name == entry.key)
          .firstOrNull;
      if (key == null ||
          entry.value is! int ||
          (entry.value! as int) < 0 ||
          (entry.value! as int) > 100) {
        return null;
      }
      scores[key] = entry.value! as int;
    }
    if (raw['reviewedOverride'] == true && scores[primary] != 100) return null;
    return SceneContext(
      primaryScene: primary,
      facets: facets.whereType<SceneFacet>(),
      activity: activity,
      scores: scores,
      reviewedOverride: raw['reviewedOverride']! as bool,
    );
  }

  bool _manifestReferencesAreValid({
    required String? primaryEventId,
    required List<String> secondaryEventIds,
    required List<String> safetyEventIds,
    required Map<String, ContextEvent> eventById,
  }) {
    bool isOpportunity(String id) {
      final event = eventById[id];
      return event != null &&
          (event.channel == ContextEventChannel.opportunity ||
              event.channel == ContextEventChannel.wildlifeOpportunity);
    }

    bool isSafety(String id) {
      final event = eventById[id];
      return event != null &&
          (event.channel == ContextEventChannel.safety ||
              event.channel == ContextEventChannel.wildlifeSafety);
    }

    if (primaryEventId != null && !isOpportunity(primaryEventId)) {
      return false;
    }
    for (final id in secondaryEventIds) {
      if (!isOpportunity(id)) return false;
    }
    for (final id in safetyEventIds) {
      if (!isSafety(id)) return false;
    }
    return true;
  }

  ContextEvent _event(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid context event');
    final value = Map<String, Object?>.from(raw);
    final channel = ContextEventChannel.values
        .where((item) => item.name == value['channel'])
        .firstOrNull;
    final source = ContextEventSource.values
        .where((item) => item.name == value['source'])
        .firstOrNull;
    final observedAt = DateTime.tryParse('${value['observedAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${value['expiresAt'] ?? ''}');
    final confidence = value['confidence'];
    final geoScope = ContextGeoScope.values
        .where((item) => item.name == value['geoScope'])
        .firstOrNull;
    final safetyLevel = ContextSafetyLevel.values
        .where((item) => item.name == value['severity'])
        .firstOrNull;
    final action = ContextAction.values
        .where((item) => item.name == value['allowedAction'])
        .firstOrNull;
    final title = value['title'];
    final sourceUrl = value['sourceUrl'];
    final sourceUri = sourceUrl is String ? Uri.tryParse(sourceUrl) : null;
    final validTitle =
        title == null ||
        (title is String &&
            title.trim().isNotEmpty &&
            title.runes.length <= 80 &&
            !title.contains(RegExp(r'[\r\n]')));
    final validAuthority = source == ContextEventSource.astronomyCatalog
        ? action == ContextAction.openAstronomyDetail &&
              title is String &&
              sourceUrl is String &&
              sourceUri != null &&
              sourceUri.scheme == 'https' &&
              sourceUri.host.isNotEmpty &&
              sourceUrl.length <= 500
        : sourceUrl == null;
    const requiredKeys = {
      'id',
      'channel',
      'source',
      'observedAt',
      'expiresAt',
      'confidence',
      'geoScope',
      'severity',
      'allowedAction',
    };
    const allowedKeys = {...requiredKeys, 'title', 'sourceUrl'};
    if (!requiredKeys.every(value.containsKey) ||
        value.keys.any((key) => !allowedKeys.contains(key)) ||
        value['id'] is! String ||
        !RegExp(
          r'^[a-z0-9][a-z0-9._-]{0,95}$',
        ).hasMatch(value['id']! as String) ||
        channel == null ||
        source == null ||
        observedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(observedAt) ||
        !_finiteIn(confidence, 0, 1) ||
        geoScope == null ||
        safetyLevel == null ||
        action == null ||
        !validTitle ||
        !validAuthority) {
      throw const FormatException('Invalid context event');
    }
    return ContextEvent(
      id: value['id']! as String,
      channel: channel,
      source: source,
      observedAt: observedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      confidence: (confidence! as num).toDouble(),
      geoScope: geoScope,
      safetyLevel: safetyLevel,
      allowedAction: action,
      title: title as String?,
      sourceUri: sourceUri,
    );
  }

  List<ShootingSession> _shootingSessions(List raw) {
    if (raw.length > 2) {
      throw const FormatException('Too many shooting sessions');
    }
    final ids = <String>{};
    return List.unmodifiable(
      raw.map((value) {
        final session = _shootingSession(value);
        if (!ids.add(session.id)) {
          throw const FormatException('Duplicate shooting session');
        }
        return session;
      }),
    );
  }

  ShootingSession _shootingSession(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid shooting session');
    final value = Map<String, Object?>.from(raw);
    const keys = {
      'id',
      'kind',
      'title',
      'startAt',
      'endAt',
      'primaryPhase',
      'conditionBand',
      'confidenceBand',
      'trend',
      'phases',
      'factors',
      'trendSamples',
      'targetCandidates',
      'recommendedCapabilities',
      'ruleVersion',
      'expiresAt',
    };
    final id = value['id'];
    final title = value['title'];
    final startsAt = DateTime.tryParse('${value['startAt'] ?? ''}')?.toUtc();
    final endsAt = DateTime.tryParse('${value['endAt'] ?? ''}')?.toUtc();
    final expiresAt = DateTime.tryParse('${value['expiresAt'] ?? ''}')?.toUtc();
    final kind = ShootingSessionKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    final primaryPhase = ShootingPhaseKind.values
        .where((item) => item.name == value['primaryPhase'])
        .firstOrNull;
    final condition = ShootingConditionBand.values
        .where((item) => item.name == value['conditionBand'])
        .firstOrNull;
    final confidence = ShootingConfidenceBand.values
        .where((item) => item.name == value['confidenceBand'])
        .firstOrNull;
    final trend = ShootingTrend.values
        .where((item) => item.name == value['trend'])
        .firstOrNull;
    final phases = value['phases'];
    final factors = value['factors'];
    final samples = value['trendSamples'];
    final targets = value['targetCandidates'];
    final capabilities = value['recommendedCapabilities'];
    if (!_hasOnlyKeys(value, keys) ||
        !keys.every(value.containsKey) ||
        id is! String ||
        !RegExp(r'^session_[a-f0-9]{24}$').hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        title.runes.length > 80 ||
        kind == null ||
        primaryPhase == null ||
        condition == null ||
        confidence == null ||
        trend == null ||
        startsAt == null ||
        endsAt == null ||
        !endsAt.isAfter(startsAt) ||
        expiresAt == null ||
        phases is! List ||
        phases.isEmpty ||
        phases.length > 5 ||
        factors is! List ||
        factors.isEmpty ||
        factors.length > 8 ||
        samples is! List ||
        samples.length < 2 ||
        samples.length > 12 ||
        targets is! List ||
        targets.length > 3 ||
        capabilities is! List ||
        capabilities.length > 4 ||
        value['ruleVersion'] is! String ||
        !RegExp(
          r'^[a-z0-9._-]{1,32}$',
        ).hasMatch(value['ruleVersion']! as String)) {
      throw const FormatException('Invalid shooting session');
    }
    final parsedPhases = phases.map(_shootingPhase).toList(growable: false);
    if (!parsedPhases.any((phase) => phase.kind == primaryPhase)) {
      throw const FormatException('Invalid shooting primary phase');
    }
    final recommendedCapabilities = <EquipmentCapability>{};
    const supportedCapabilities = {
      EquipmentCapability.tripod,
      EquipmentCapability.wideAngle,
      EquipmentCapability.telephoto,
      EquipmentCapability.filter,
      EquipmentCapability.weatherProtection,
      EquipmentCapability.headlamp,
    };
    for (final raw in capabilities) {
      final capability = supportedCapabilities
          .where((item) => item.id == raw)
          .firstOrNull;
      if (capability == null || !recommendedCapabilities.add(capability)) {
        throw const FormatException('Invalid recommended capability');
      }
    }
    return ShootingSession(
      id: id,
      kind: kind,
      title: title.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      primaryPhase: primaryPhase,
      conditionBand: condition,
      confidenceBand: confidence,
      trend: trend,
      phases: parsedPhases,
      factors: factors.map(_shootingFactor),
      trendSamples: samples.map(_shootingTrendSample),
      targetCandidates: targets.map(_shootingTarget),
      recommendedCapabilities: recommendedCapabilities,
      ruleVersion: value['ruleVersion']! as String,
      expiresAt: expiresAt,
    );
  }

  ShootingSessionPhase _shootingPhase(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid shooting phase');
    final value = Map<String, Object?>.from(raw);
    if (!_hasExactKeys(value, const {
      'kind',
      'startAt',
      'peakAt',
      'endAt',
      'conditionBand',
      'directionDegrees',
    })) {
      throw const FormatException('Invalid shooting phase');
    }
    final kind = ShootingPhaseKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    final condition = ShootingConditionBand.values
        .where((item) => item.name == value['conditionBand'])
        .firstOrNull;
    final start = DateTime.tryParse('${value['startAt'] ?? ''}')?.toUtc();
    final peak = DateTime.tryParse('${value['peakAt'] ?? ''}')?.toUtc();
    final end = DateTime.tryParse('${value['endAt'] ?? ''}')?.toUtc();
    final direction = value['directionDegrees'];
    if (kind == null ||
        condition == null ||
        start == null ||
        peak == null ||
        end == null ||
        peak.isBefore(start) ||
        end.isBefore(peak) ||
        !_finiteIn(direction, 0, 359.999)) {
      throw const FormatException('Invalid shooting phase');
    }
    return ShootingSessionPhase(
      kind: kind,
      startsAt: start,
      peaksAt: peak,
      endsAt: end,
      conditionBand: condition,
      directionDegrees: (direction! as num).toDouble(),
    );
  }

  ShootingSessionFactor _shootingFactor(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid shooting factor');
    final value = Map<String, Object?>.from(raw);
    final sourceAt = DateTime.tryParse('${value['sourceAt'] ?? ''}')?.toUtc();
    final effect = ShootingFactorEffect.values
        .where((item) => item.name == value['effect'])
        .firstOrNull;
    if (!_hasExactKeys(value, const {
          'id',
          'effect',
          'label',
          'value',
          'sourceAt',
        }) ||
        value['id'] is! String ||
        !const {
          'cloud',
          'wind',
          'precipitation',
          'visibility',
          'dataCoverage',
        }.contains(value['id']) ||
        effect == null ||
        value['label'] is! String ||
        (value['label'] as String).trim().isEmpty ||
        (value['label'] as String).runes.length > 40 ||
        value['value'] is! String ||
        (value['value'] as String).trim().isEmpty ||
        (value['value'] as String).runes.length > 80 ||
        sourceAt == null) {
      throw const FormatException('Invalid shooting factor');
    }
    return ShootingSessionFactor(
      id: value['id']! as String,
      effect: effect,
      label: (value['label']! as String).trim(),
      value: (value['value']! as String).trim(),
      sourceAt: sourceAt,
    );
  }

  ShootingSessionTrendSample _shootingTrendSample(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid shooting trend sample');
    }
    final value = Map<String, Object?>.from(raw);
    final at = DateTime.tryParse('${value['at'] ?? ''}')?.toUtc();
    if (!_hasExactKeys(value, const {
          'at',
          'conditionIndex',
          'cloudCoverPercent',
          'windSpeedMps',
          'precipitationMm',
        }) ||
        at == null ||
        value['conditionIndex'] is! int ||
        !_finiteIn(value['conditionIndex'], 0, 100) ||
        (value['cloudCoverPercent'] != null &&
            !_finiteIn(value['cloudCoverPercent'], 0, 100)) ||
        !_finiteIn(value['windSpeedMps'], 0, 150) ||
        !_finiteIn(value['precipitationMm'], 0, 2000)) {
      throw const FormatException('Invalid shooting trend sample');
    }
    return ShootingSessionTrendSample(
      at: at,
      conditionIndex: value['conditionIndex']! as int,
      cloudCoverPercent: (value['cloudCoverPercent'] as num?)?.toDouble(),
      windSpeedMps: (value['windSpeedMps']! as num).toDouble(),
      precipitationMm: (value['precipitationMm']! as num).toDouble(),
    );
  }

  ShootingTarget _shootingTarget(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid shooting target');
    final value = Map<String, Object?>.from(raw);
    final coordinate = value['coordinate'];
    final reviewedAt = DateTime.tryParse(
      '${value['reviewedAt'] ?? ''}',
    )?.toUtc();
    final shorelineSide = ShootingShorelineSide.values
        .where((item) => item.name == value['shorelineSide'])
        .firstOrNull;
    final reviewReference = _httpsUri(value['reviewReference']);
    final sourceUrl = _httpsUri(value['sourceUrl']);
    final sessions = value['supportedSessions'];
    final accessModes = value['accessModes'];
    if (!_hasExactKeys(value, const {
          'id',
          'name',
          'kind',
          'coordinate',
          'supportedSessions',
          'viewBearingDegrees',
          'bearingToleranceDegrees',
          'accessModes',
          'leadTimeMinutes',
          'arrivalRadiusMeters',
          'shorelineSide',
          'reviewedAt',
          'reviewReference',
          'sourceAttribution',
          'sourceLicense',
          'sourceUrl',
        }) ||
        value['id'] is! String ||
        !RegExp(r'^target_[a-f0-9]{24}$').hasMatch(value['id']! as String) ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        (value['name'] as String).runes.length > 200 ||
        value['kind'] != 'lakeshore' ||
        coordinate is! Map ||
        sessions is! List ||
        sessions.isEmpty ||
        sessions.length > 2 ||
        accessModes is! List ||
        accessModes.isEmpty ||
        accessModes.length > 2 ||
        !_finiteIn(value['viewBearingDegrees'], 0, 359.999) ||
        !_finiteIn(value['bearingToleranceDegrees'], 5, 90) ||
        value['leadTimeMinutes'] is! int ||
        !_finiteIn(value['leadTimeMinutes'], 0, 180) ||
        value['arrivalRadiusMeters'] is! int ||
        !_finiteIn(value['arrivalRadiusMeters'], 25, 1000) ||
        shorelineSide == null ||
        reviewedAt == null ||
        reviewReference == null ||
        value['sourceAttribution'] is! String ||
        (value['sourceAttribution'] as String).trim().isEmpty ||
        (value['sourceAttribution'] as String).runes.length > 500 ||
        value['sourceLicense'] is! String ||
        (value['sourceLicense'] as String).trim().isEmpty ||
        (value['sourceLicense'] as String).runes.length > 100 ||
        sourceUrl == null) {
      throw const FormatException('Invalid shooting target');
    }
    final point = Map<String, Object?>.from(coordinate);
    if (!_hasExactKeys(point, const {'latitude', 'longitude', 'system'}) ||
        point['system'] != 'wgs84' ||
        !_finiteIn(point['latitude'], -90, 90) ||
        !_finiteIn(point['longitude'], -180, 180)) {
      throw const FormatException('Invalid shooting target coordinate');
    }
    final supported = sessions
        .map(
          (item) => ShootingSessionKind.values
              .where((value) => value.name == item)
              .firstOrNull,
        )
        .toList(growable: false);
    final modes = accessModes
        .map(
          (item) => ShootingTravelMode.values
              .where((value) => value.name == item)
              .firstOrNull,
        )
        .toList(growable: false);
    if (supported.any((item) => item == null) ||
        modes.any((item) => item == null)) {
      throw const FormatException('Invalid shooting target capability');
    }
    return ShootingTarget(
      id: value['id']! as String,
      name: (value['name']! as String).trim(),
      coordinate: GeoPoint(
        latitude: (point['latitude']! as num).toDouble(),
        longitude: (point['longitude']! as num).toDouble(),
      ),
      supportedSessions: supported.cast<ShootingSessionKind>(),
      viewBearingDegrees: (value['viewBearingDegrees']! as num).toDouble(),
      bearingToleranceDegrees: (value['bearingToleranceDegrees']! as num)
          .toDouble(),
      accessModes: modes.cast<ShootingTravelMode>(),
      leadTimeMinutes: value['leadTimeMinutes']! as int,
      arrivalRadiusMeters: value['arrivalRadiusMeters']! as int,
      shorelineSide: shorelineSide,
      reviewedAt: reviewedAt,
      reviewReference: reviewReference,
      sourceAttribution: (value['sourceAttribution']! as String).trim(),
      sourceLicense: (value['sourceLicense']! as String).trim(),
      sourceUrl: sourceUrl,
    );
  }
}
