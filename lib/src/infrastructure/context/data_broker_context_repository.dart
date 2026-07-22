import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_action.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/entry/entry_provenance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

const _v5ResponseKeys = <String>{
  'contractVersion',
  'contextId',
  'snapshotRevision',
  'generatedAt',
  'expiresAt',
  'sourceRevisions',
  'stale',
  'environment',
  'facts',
  'entries',
  'refreshHints',
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
      final headers = <String, String>{'Authorization': 'Bearer $serviceToken'};
      final debugSession = debugSimulationSession;
      if (debugSession != null) {
        headers['X-LumaNest-Debug-Session'] = debugSession;
        headers['X-LumaNest-Debug-Contract'] = '5';
      }
      final body = await transport.post(
        uri,
        headers: headers,
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
    if (session != null) {
      headers['X-LumaNest-Debug-Session'] = session;
      headers['X-LumaNest-Debug-Contract'] = '5';
    }
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
      'contractVersion': 5,
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
    if (body['contractVersion'] == 5) {
      return _parseV5(body, location: location, fallback: fallback);
    }
    throw const RemoteContextFailure(RemoteContextFailureKind.response);
  }

  ContextSnapshot _parseV5(
    Map<String, Object?> body, {
    required GeoPoint location,
    ContextSnapshot? fallback,
  }) {
    if (!_hasExactKeys(body, _v5ResponseKeys) ||
        body['contractVersion'] != 5 ||
        body['contextId'] is! String ||
        body['snapshotRevision'] is! int ||
        body['environment'] is! Map ||
        body['facts'] is! Map ||
        body['entries'] is! List ||
        body['sourceRevisions'] is! Map ||
        body['refreshHints'] is! Map) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final environment = Map<String, Object?>.from(body['environment']! as Map);
    final facts = Map<String, Object?>.from(body['facts']! as Map);
    final sourceRevisions = Map<String, Object?>.from(
      body['sourceRevisions']! as Map,
    );
    final refreshHints = Map<String, Object?>.from(
      body['refreshHints']! as Map,
    );
    if (!_hasExactKeys(environment, const {
          'scene',
          'dataFreshness',
          'weather',
          'sunMoon',
          'astronomy',
          'route',
          'sceneContext',
          'allowedActions',
        }) ||
        !_hasExactKeys(facts, const {'events', 'shootingSessions'}) ||
        !_hasExactKeys(sourceRevisions, const {
          'weather',
          'solar',
          'astronomy',
          'scene',
          'route',
        }) ||
        sourceRevisions.values.any((value) => value is! int || value < 1) ||
        !_hasExactKeys(refreshHints, const {
          'weather',
          'airQuality',
          'solar',
          'astronomy',
          'opportunities',
        }) ||
        refreshHints.values.any((value) => value is! String)) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final scene = SceneType.values
        .where((value) => value.name == environment['scene'])
        .firstOrNull;
    final freshness = Map<String, Object?>.from(
      environment['dataFreshness']! as Map,
    );
    final weatherState = Map<String, Object?>.from(
      environment['weather']! as Map,
    );
    final sunMoon = Map<String, Object?>.from(environment['sunMoon']! as Map);
    final astronomy = _astronomyGeometry(environment['astronomy']);
    final route = Map<String, Object?>.from(environment['route']! as Map);
    final generatedAt = DateTime.tryParse('${body['generatedAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${body['expiresAt'] ?? ''}');
    final dataFreshness = ContextDataFreshness.values
        .where((value) => value.name == freshness['context'])
        .firstOrNull;
    final weatherFreshness = ContextDataFreshness.values
        .where((value) => value.name == freshness['weather'])
        .firstOrNull;
    final weatherObservedAt = DateTime.tryParse(
      '${freshness['weatherObservedAt'] ?? ''}',
    );
    final weatherType = WeatherType.values
        .where((value) => value.name == weatherState['condition'])
        .firstOrNull;
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
    final sceneContext = _sceneContext(environment['sceneContext']);
    final events = (facts['events']! as List)
        .map(_event)
        .toList(growable: false);
    final shootingSessions = _shootingSessions(
      facts['shootingSessions']! as List,
    );
    final actions = (environment['allowedActions']! as List)
        .map(
          (raw) => raw is String
              ? ContextAction.values
                    .where((value) => value.name == raw)
                    .firstOrNull
              : null,
        )
        .toList(growable: false);
    final entries = (body['entries']! as List)
        .map(_entryV5)
        .toList(growable: false);
    if (!RegExp(r'^ctx_[a-f0-9]{24}$').hasMatch(body['contextId']! as String) ||
        scene == null ||
        sceneContext == null ||
        generatedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(generatedAt) ||
        dataFreshness == null ||
        weatherFreshness == null ||
        weatherObservedAt == null ||
        weatherType == null ||
        sunDayPhase == null ||
        moonPhase == null ||
        astronomy == null ||
        routeMode == null ||
        routeStage == null ||
        !_hasExactKeys(route, const {'mode', 'stage', 'active'}) ||
        route['active'] is! bool ||
        (route['active'] == true) != (routeStage == ContextRouteStage.active) ||
        (routeMode == ContextRouteMode.none) !=
            (routeStage == ContextRouteStage.none) ||
        actions.any((action) => action == null) ||
        entries.any((entry) => entry == null) ||
        !_finiteIn(weatherState['windSpeedMps'], 0, 150) ||
        !_finiteIn(weatherState['precipitationMm'], 0, 2000) ||
        !_finiteIn(weatherState['visibilityKm'], 0, 500) ||
        !_finiteIn(sunMoon['moonIllumination'], 0, 1)) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final isStale =
        body['stale'] == true ||
        dataFreshness == ContextDataFreshness.stale ||
        weatherFreshness == ContextDataFreshness.stale;
    return ContextSnapshot(
      id: body['contextId']! as String,
      observedAt: weatherObservedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      primaryScene: scene,
      sceneContext: sceneContext,
      dayPhase: sunDayPhase,
      weather: weatherType,
      activeRoute: route['active'] == true,
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
      shootingSessions: isStale ? const [] : shootingSessions,
      wildlifeActivity: fallback?.wildlifeActivity,
      location: location,
      temperatureCelsius: (weatherState['temperatureCelsius'] as num?)
          ?.toDouble(),
      windSpeedMetersPerSecond: (weatherState['windSpeedMps'] as num)
          .toDouble(),
      windDirectionDegrees: (weatherState['windDirectionDegrees'] as num?)
          ?.toDouble(),
      visibilityKilometers: (weatherState['visibilityKm'] as num).toDouble(),
      precipitationMillimeters: (weatherState['precipitationMm'] as num)
          .toDouble(),
      cloudCoverPercent: (weatherState['cloudCoverPercent'] as num?)
          ?.toDouble(),
      airQualityIndex: weatherState['airQualityIndex'] as int?,
      airQualityCategory: weatherState['airQualityCategory'] as String?,
      primaryPollutant: weatherState['primaryPollutant'] as String?,
      airQualityObservedAt: DateTime.tryParse(
        '${weatherState['airQualityObservedAt'] ?? ''}',
      )?.toUtc(),
      airQualityStale: weatherState['airQualityStale'] == true,
      solarElevationDegrees: (sunMoon['sunElevationDegrees'] as num?)
          ?.toDouble(),
      solarAzimuthDegrees: (sunMoon['sunAzimuthDegrees'] as num?)?.toDouble(),
      sunrise: fallback?.sunrise,
      sunset: fallback?.sunset,
      isStale: isStale,
      remoteGeneratedAt: generatedAt.toUtc(),
      dataFreshness: dataFreshness,
      moonPhase: moonPhase,
      moonIllumination: (sunMoon['moonIllumination'] as num).toDouble(),
      astronomyGeometry: astronomy,
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: actions.cast<ContextAction>(),
      entries: entries.whereType<ContextEntry>().toList(growable: false),
      canonicalEntriesPresent: true,
    );
  }

  AstronomyGeometry? _astronomyGeometry(Object? raw) {
    if (raw is! Map) return null;
    final value = Map<String, Object?>.from(raw);
    if (!_hasExactKeys(value, const {
      'status',
      'astronomicalNight',
      'moonAltitudeDegrees',
      'moonAzimuthDegrees',
      'moonriseAt',
      'moonsetAt',
      'moonPhase',
      'moonIllumination',
      'galacticCenterAltitudeDegrees',
      'galacticCenterAzimuthDegrees',
      'galacticCenterWindow',
    })) {
      return null;
    }
    final status = AstronomyGeometryStatus.values
        .where((item) => item.name == value['status'])
        .firstOrNull;
    if (status == null) return null;
    if (status == AstronomyGeometryStatus.unavailable) {
      if (value.entries.any(
        (entry) => entry.key != 'status' && entry.value != null,
      )) {
        return null;
      }
      return const AstronomyGeometry(
        status: AstronomyGeometryStatus.unavailable,
      );
    }
    final moonPhase = MoonPhase.values
        .where((item) => item.name == value['moonPhase'])
        .firstOrNull;
    final moonrise = _optionalDate(value['moonriseAt']);
    final moonset = _optionalDate(value['moonsetAt']);
    final window = _galacticCenterWindow(value['galacticCenterWindow']);
    if (value['astronomicalNight'] is! bool ||
        moonPhase == null ||
        !_finiteIn(value['moonAltitudeDegrees'], -90, 90) ||
        !_finiteIn(value['moonAzimuthDegrees'], 0, 359.999999) ||
        !_finiteIn(value['moonIllumination'], 0, 1) ||
        !_finiteIn(value['galacticCenterAltitudeDegrees'], -90, 90) ||
        !_finiteIn(value['galacticCenterAzimuthDegrees'], 0, 359.999999) ||
        (value['moonriseAt'] != null && moonrise == null) ||
        (value['moonsetAt'] != null && moonset == null) ||
        (value['galacticCenterWindow'] != null && window == null)) {
      return null;
    }
    return AstronomyGeometry(
      status: status,
      astronomicalNight: value['astronomicalNight']! as bool,
      moonAltitudeDegrees: (value['moonAltitudeDegrees']! as num).toDouble(),
      moonAzimuthDegrees: (value['moonAzimuthDegrees']! as num).toDouble(),
      moonriseAt: moonrise,
      moonsetAt: moonset,
      moonPhase: moonPhase,
      moonIllumination: (value['moonIllumination']! as num).toDouble(),
      galacticCenterAltitudeDegrees:
          (value['galacticCenterAltitudeDegrees']! as num).toDouble(),
      galacticCenterAzimuthDegrees:
          (value['galacticCenterAzimuthDegrees']! as num).toDouble(),
      galacticCenterWindow: window,
    );
  }

  GalacticCenterWindow? _galacticCenterWindow(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map ||
        !_hasExactKeys(raw, const {
          'startAt',
          'peakAt',
          'endAt',
          'peakAltitudeDegrees',
        })) {
      return null;
    }
    final start = DateTime.tryParse('${raw['startAt'] ?? ''}')?.toUtc();
    final peak = DateTime.tryParse('${raw['peakAt'] ?? ''}')?.toUtc();
    final end = DateTime.tryParse('${raw['endAt'] ?? ''}')?.toUtc();
    if (start == null ||
        peak == null ||
        end == null ||
        peak.isBefore(start) ||
        peak.isAfter(end) ||
        !_finiteIn(raw['peakAltitudeDegrees'], 10, 90)) {
      return null;
    }
    return GalacticCenterWindow(
      startAt: start,
      peakAt: peak,
      endAt: end,
      peakAltitudeDegrees: (raw['peakAltitudeDegrees']! as num).toDouble(),
    );
  }

  DateTime? _optionalDate(Object? raw) =>
      raw == null ? null : DateTime.tryParse('$raw')?.toUtc();

  ContextEntry? _entryV5(Object? raw) {
    if (raw is! Map) return null;
    final value = Map<String, Object?>.from(raw);
    final actions = value['actions'];
    final presentation = value['presentation'];
    final payload = value['payload'];
    final provenance = value['provenance'];
    if (actions is! List ||
        actions.isEmpty ||
        presentation is! Map ||
        payload is! Map ||
        provenance is! List) {
      return null;
    }
    final actionRaw = Map<String, Object?>.from(actions.first as Map);
    final actionType = EntryActionType.values
        .where((item) => item.name == actionRaw['type'])
        .firstOrNull;
    final variant = EntryPresentationVariant.values
        .where((item) => item.name == presentation['variant'])
        .firstOrNull;
    final kind = EntryKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    final priority = EntryPriority.values
        .where((item) => item.name == value['basePriority'])
        .firstOrNull;
    final severity = EntrySeverity.values
        .where((item) => item.name == value['severity'])
        .firstOrNull;
    final freshness = EntryFreshness.values
        .where((item) => item.name == value['freshness'])
        .firstOrNull;
    final geo = ContextGeoScope.values
        .where((item) => item.name == value['geoScope'])
        .firstOrNull;
    final observedAt = DateTime.tryParse('${value['observedAt'] ?? ''}');
    final validFrom = DateTime.tryParse('${value['validFrom'] ?? ''}');
    final expiresAt = DateTime.tryParse('${value['expiresAt'] ?? ''}');
    if (actionType == null ||
        variant == null ||
        kind == null ||
        priority == null ||
        severity == null ||
        freshness == null ||
        geo == null ||
        observedAt == null ||
        validFrom == null ||
        expiresAt == null ||
        value['revision'] is! int ||
        value['evidenceConfidence'] is! num ||
        presentation['title'] is! String ||
        payload['type'] is! String) {
      return null;
    }
    final payloadType = payload['type'];
    final entryPayload = payloadType == 'safety'
        ? SafetyEntryPayload(
            eventId:
                (payload['eventId'] as String?) ?? value['sourceId'] as String,
            action: ContextAction.values.firstWhere(
              (item) => item.name == actionRaw['type'],
              orElse: () => ContextAction.openSafetyDetail,
            ),
          )
        : payloadType == 'opportunity'
        ? OpportunityEntryPayload(
            definitionId:
                (payload['definitionId'] as String?) ??
                value['sourceId'] as String,
            instanceId:
                (payload['instanceId'] as String?) ??
                value['sourceId'] as String,
            sessionId: payload['sessionId'] as String?,
          )
        : const SystemEntryPayload(stateCode: 'remote');
    final provenanceEntries = provenance
        .map((item) {
          final map = Map<String, Object?>.from(item as Map);
          final at = DateTime.tryParse('${map['observedAt'] ?? ''}');
          return at == null
              ? null
              : EntryProvenance(sourceId: '${map['sourceId']}', observedAt: at);
        })
        .whereType<EntryProvenance>()
        .toList(growable: false);
    return ContextEntry(
      id: value['id']! as String,
      kind: kind,
      sourceNamespace: value['sourceNamespace']! as String,
      sourceId: value['sourceId']! as String,
      revision: value['revision']! as int,
      observedAt: observedAt,
      validFrom: validFrom,
      expiresAt: expiresAt,
      freshness: freshness,
      evidenceConfidence: (value['evidenceConfidence']! as num).toDouble(),
      basePriority: priority,
      severity: severity,
      geoScope: EntryGeoScope(type: geo),
      allowedSurfaces: (value['allowedSurfaces']! as List)
          .map(
            (item) => EntrySurface.values
                .where((surface) => surface.name == item)
                .firstOrNull,
          )
          .whereType<EntrySurface>()
          .toSet(),
      actions: [
        EntryAction(
          type: actionType,
          targetId: actionRaw['targetId'] as String?,
          query: actionRaw['query'] as String?,
        ),
      ],
      presentation: EntryPresentation(
        variant: variant,
        eyebrow:
            presentation['shortLabel'] as String? ??
            presentation['title']! as String,
        title: presentation['title']! as String,
        detail: presentation['fallbackSummary'] as String? ?? '',
        timeLabel: '环境更新后持续观察',
        actionLabel: actionType.name == 'openSafetyDetail' ? '查看安全建议' : '查看',
        accent: kind == EntryKind.safety ? EntryAccent.danger : EntryAccent.sky,
      ),
      payload: entryPayload,
      provenance: provenanceEntries,
      dedupeKey: value['dedupeKey']! as String,
      suppressionKeys: (value['suppressionKeys']! as List)
          .whereType<String>()
          .toSet(),
      contentFingerprint: value['contentFingerprint']! as String,
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
