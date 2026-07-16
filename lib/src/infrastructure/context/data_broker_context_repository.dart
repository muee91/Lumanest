import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

const _v2ResponseKeys = <String>{
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
};

const _v3ResponseKeys = <String>{..._v2ResponseKeys, 'opportunities'};

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> keys) {
  return value.length == keys.length && value.keys.every(keys.contains);
}

bool _hasOnlyKeys(Map<Object?, Object?> value, Set<String> keys) =>
    value.keys.every(keys.contains);

bool _finiteIn(Object? value, double minimum, double maximum) {
  return value is num && value.isFinite && value >= minimum && value <= maximum;
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

class DataBrokerContextRepository implements RemoteContextRepository {
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
  Future<ContextSnapshot> enrich({
    required ContextSnapshot base,
    required WeatherObservation weather,
    required SolarState solar,
  }) async {
    final location = base.location;
    if (location == null) {
      throw const RemoteContextFailure(RemoteContextFailureKind.configuration);
    }
    return _post(
      request: _legacyRequest(base, weather, solar),
      location: location,
      fallback: base,
    );
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
        throw const RemoteContextFailure(
          RemoteContextFailureKind.unsupportedContract,
        );
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
      'contractVersion': 3,
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
        if (route.hasRoute && corridor?.isUsable == true)
          ...corridor!.toRequest(),
      },
    };
  }

  Map<String, Object?> _legacyRequest(
    ContextSnapshot base,
    WeatherObservation weather,
    SolarState solar,
  ) {
    final scene = base.primaryScene;
    return {
      'contractVersion': 3,
      'coordinate': {
        'latitude': base.location!.latitude,
        'longitude': base.location!.longitude,
        'system': 'wgs84',
      },
      'observedAt': base.observedAt.toUtc().toIso8601String(),
      'locale': 'zh-CN',
      'intent': 'photography',
      'route': {'mode': base.routeMode.name, 'stage': base.routeStage.name},
      'evidence': {
        'urban': scene == SceneType.city,
        'waterBody': scene == SceneType.lake,
        'mountainous': scene == SceneType.mountain,
        'aridLand': scene == SceneType.desert,
        'settlement': scene == SceneType.village,
      },
      'weather': {
        'observedAt': weather.observedAt.toUtc().toIso8601String(),
        'condition': switch (weather.condition) {
          WeatherCondition.thunder => 'rain',
          _ => weather.condition.name,
        },
        'windSpeedMps': weather.windSpeedMetersPerSecond,
        'precipitationMm': weather.precipitationMillimeters,
        'visibilityKm': weather.visibilityKilometers,
        'thunder': weather.hasThunder,
        'stale': base.isStale,
        'temperatureCelsius': weather.temperatureCelsius,
        'windDirectionDegrees': weather.windDirectionDegrees,
        'cloudCoverPercent': weather.cloudCoverPercent,
      },
      'solar': {
        'dayPhase': solar.dayPhase.name,
        'elevationDegrees': solar.elevationDegrees,
        'azimuthDegrees': solar.azimuthDegrees,
      },
    };
  }

  ContextSnapshot _parse(
    Map<String, Object?> body, {
    required GeoPoint location,
    ContextSnapshot? fallback,
  }) {
    final contractVersion = body['contractVersion'];
    final isV3 = contractVersion == 3;
    if (!_hasExactKeys(body, isV3 ? _v3ResponseKeys : _v2ResponseKeys) ||
        (contractVersion != 2 && contractVersion != 3) ||
        body['contextId'] is! String ||
        body['scene'] is! String ||
        body['events'] is! List ||
        body['dataFreshness'] is! Map ||
        body['weather'] is! Map ||
        body['sunMoon'] is! Map ||
        body['route'] is! Map ||
        body['manifest'] is! Map ||
        body['allowedActions'] is! List ||
        (isV3 && body['opportunities'] is! List)) {
      throw const RemoteContextFailure(RemoteContextFailureKind.response);
    }
    final scene = SceneType.values
        .where((value) => value.name == body['scene'])
        .firstOrNull;
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
    final opportunities = isV3
        ? _opportunities(body['opportunities'] as List)
        : const <PhotographyOpportunity>[];
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
      photographyOpportunities:
          body['stale']! as bool ||
              dataFreshness == ContextDataFreshness.stale ||
              weatherFreshness == ContextDataFreshness.stale
          ? const []
          : opportunities,
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
    final validAuthority = action == ContextAction.openAuthority
        ? source == ContextEventSource.astronomyCatalog &&
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
        !RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(value['id']! as String) ||
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

  List<PhotographyOpportunity> _opportunities(List raw) {
    if (raw.length > 8) {
      throw const FormatException('Too many photography opportunities');
    }
    final ids = <String>{};
    return List.unmodifiable(
      raw.map((value) {
        final opportunity = _opportunity(value);
        if (!ids.add(opportunity.id)) {
          throw const FormatException('Duplicate photography opportunity');
        }
        return opportunity;
      }),
    );
  }

  PhotographyOpportunity _opportunity(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid photography opportunity');
    }
    final value = Map<String, Object?>.from(raw);
    const keys = {
      'id',
      'kind',
      'startAt',
      'peakAt',
      'endAt',
      'score',
      'confidence',
      'geoScope',
      'directionDegrees',
      'evidence',
      'primaryAction',
      'fallbackAction',
      'equipmentHints',
      'target',
      'corridor',
    };
    final kind = PhotographyOpportunityKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    final scope = PhotographyOpportunityGeoScope.values
        .where((item) => item.name == value['geoScope'])
        .firstOrNull;
    final primaryAction = ContextAction.values
        .where((item) => item.name == value['primaryAction'])
        .firstOrNull;
    final fallbackAction = value['fallbackAction'] == null
        ? null
        : ContextAction.values
              .where((item) => item.name == value['fallbackAction'])
              .firstOrNull;
    final startsAt = DateTime.tryParse('${value['startAt'] ?? ''}')?.toUtc();
    final peaksAt = DateTime.tryParse('${value['peakAt'] ?? ''}')?.toUtc();
    final endsAt = DateTime.tryParse('${value['endAt'] ?? ''}')?.toUtc();
    final id = value['id'];
    final score = value['score'];
    final confidence = value['confidence'];
    final direction = value['directionDegrees'];
    final evidence = value['evidence'];
    final hints = value['equipmentHints'];
    final target = _target(value['target']);
    final corridor = _corridor(value['corridor']);
    if (!_hasOnlyKeys(value, keys) ||
        id is! String ||
        !RegExp(r'^photo-[a-z0-9_-]{1,58}$').hasMatch(id) ||
        kind == null ||
        scope == null ||
        startsAt == null ||
        peaksAt == null ||
        endsAt == null ||
        peaksAt.isBefore(startsAt) ||
        endsAt.isBefore(peaksAt) ||
        score is! int ||
        score < 0 ||
        score > 100 ||
        !_finiteIn(confidence, 0, 1) ||
        (direction != null && !_finiteIn(direction, 0, 359.999)) ||
        primaryAction == null ||
        (value['fallbackAction'] != null && fallbackAction == null) ||
        evidence is! List ||
        evidence.isEmpty ||
        evidence.length > 4 ||
        hints is! List ||
        hints.length > 4) {
      throw const FormatException('Invalid photography opportunity');
    }
    final decodedEvidence = <PhotographyEvidence>[];
    for (var index = 0; index < evidence.length; index += 1) {
      final entry = evidence[index];
      if (entry is! Map) throw const FormatException('Invalid evidence');
      final item = Map<String, Object?>.from(entry);
      if (!_hasExactKeys(item, const {'label', 'value'}) ||
          item['label'] is! String ||
          item['value'] is! String ||
          (item['label'] as String).trim().isEmpty ||
          (item['label'] as String).runes.length > 40 ||
          (item['value'] as String).trim().isEmpty ||
          (item['value'] as String).runes.length > 80) {
        throw const FormatException('Invalid photography evidence');
      }
      final label = (item['label'] as String).trim();
      decodedEvidence.add(
        PhotographyEvidence(
          id: '$id:$index',
          kind: _evidenceKind(label),
          statement: '$label ${(item['value'] as String).trim()}',
          confidence: (confidence as num).toDouble(),
        ),
      );
    }
    final equipmentHints = <String>[];
    for (final hint in hints) {
      if (hint is! String ||
          hint.trim().isEmpty ||
          hint.runes.length > 40 ||
          hint.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException('Invalid equipment hint');
      }
      equipmentHints.add(hint.trim());
    }
    return PhotographyOpportunity(
      id: id,
      kind: kind,
      title: _titleFor(kind),
      startsAt: startsAt,
      peaksAt: peaksAt,
      expiresAt: endsAt,
      score: score,
      confidence: (confidence as num).toDouble(),
      geoScope: scope,
      directionDegrees: (direction as num?)?.toDouble(),
      primaryAction: primaryAction,
      fallbackAction: fallbackAction,
      evidence: decodedEvidence,
      equipmentHints: equipmentHints,
      target: target,
      corridor: corridor,
    );
  }

  PhotographyTarget? _target(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) throw const FormatException('Invalid photography target');
    final value = Map<String, Object?>.from(raw);
    final coordinate = value['coordinate'];
    if (!_hasExactKeys(value, const {
          'id',
          'name',
          'kind',
          'coordinate',
          'arrivalDeadline',
        }) ||
        coordinate is! Map) {
      throw const FormatException('Invalid photography target');
    }
    final point = Map<String, Object?>.from(coordinate);
    final kind = PhotographyTargetKind.values
        .where((item) => item.name == value['kind'])
        .firstOrNull;
    final latitude = point['latitude'];
    final longitude = point['longitude'];
    final deadline = DateTime.tryParse(
      '${value['arrivalDeadline'] ?? ''}',
    )?.toUtc();
    if (!_hasExactKeys(point, const {'latitude', 'longitude', 'system'}) ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        (value['id'] as String).length > 160 ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        (value['name'] as String).runes.length > 80 ||
        kind == null ||
        point['system'] != 'wgs84' ||
        !_finiteIn(latitude, -90, 90) ||
        !_finiteIn(longitude, -180, 180) ||
        deadline == null) {
      throw const FormatException('Invalid photography target');
    }
    return PhotographyTarget(
      id: value['id'] as String,
      name: (value['name'] as String).trim(),
      kind: kind,
      coordinate: GeoPoint(
        latitude: (latitude as num).toDouble(),
        longitude: (longitude as num).toDouble(),
      ),
      arrivalDeadline: deadline,
    );
  }

  PhotographyCorridor? _corridor(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw const FormatException('Invalid photography corridor');
    }
    final value = Map<String, Object?>.from(raw);
    final observations = value['observations'];
    if (!_hasExactKeys(value, const {'routeId', 'observations'}) ||
        value['routeId'] is! String ||
        (value['routeId'] as String).isEmpty ||
        (value['routeId'] as String).length > 160 ||
        observations is! List ||
        observations.length > 3) {
      throw const FormatException('Invalid photography corridor');
    }
    final result = <PhotographyCorridorObservation>[];
    for (final rawItem in observations) {
      if (rawItem is! Map) {
        throw const FormatException('Invalid corridor observation');
      }
      final item = Map<String, Object?>.from(rawItem);
      const keys = {
        'progress',
        'expectedAt',
        'condition',
        'cloudCoverPercent',
        'windSpeedMps',
        'precipitationMm',
        'thunder',
        'sunAzimuthDegrees',
        'opportunityId',
      };
      final expectedAt = DateTime.tryParse(
        '${item['expectedAt'] ?? ''}',
      )?.toUtc();
      if (!_hasExactKeys(item, keys) ||
          !_finiteIn(item['progress'], 0, 1) ||
          expectedAt == null ||
          item['condition'] is! String ||
          (item['condition'] as String).trim().isEmpty ||
          (item['condition'] as String).runes.length > 80 ||
          !_finiteIn(item['windSpeedMps'], 0, 150) ||
          !_finiteIn(item['precipitationMm'], 0, 500) ||
          item['thunder'] is! bool ||
          (item['cloudCoverPercent'] != null &&
              !_finiteIn(item['cloudCoverPercent'], 0, 100)) ||
          (item['sunAzimuthDegrees'] != null &&
              !_finiteIn(item['sunAzimuthDegrees'], 0, 359.999)) ||
          (item['opportunityId'] != null &&
              (item['opportunityId'] is! String ||
                  (item['opportunityId'] as String).isEmpty))) {
        throw const FormatException('Invalid corridor observation');
      }
      result.add(
        PhotographyCorridorObservation(
          progress: (item['progress'] as num).toDouble(),
          expectedAt: expectedAt,
          condition: (item['condition'] as String).trim(),
          windSpeedMps: (item['windSpeedMps'] as num).toDouble(),
          precipitationMm: (item['precipitationMm'] as num).toDouble(),
          thunder: item['thunder'] as bool,
          cloudCoverPercent: (item['cloudCoverPercent'] as num?)?.toDouble(),
          sunAzimuthDegrees: (item['sunAzimuthDegrees'] as num?)?.toDouble(),
          opportunityId: item['opportunityId'] as String?,
        ),
      );
    }
    return PhotographyCorridor(
      routeId: value['routeId'] as String,
      observations: result,
    );
  }

  PhotographyEvidenceKind _evidenceKind(String label) => switch (label) {
    '时段' => PhotographyEvidenceKind.light,
    '目录' => PhotographyEvidenceKind.astronomy,
    '风速' || '云量' || '预报' => PhotographyEvidenceKind.weather,
    _ => PhotographyEvidenceKind.weather,
  };

  String _titleFor(PhotographyOpportunityKind kind) => switch (kind) {
    PhotographyOpportunityKind.blueHour => '蓝调窗口',
    PhotographyOpportunityKind.reflection => '倒影窗口',
    PhotographyOpportunityKind.alpenglow => '日照金山窗口',
    PhotographyOpportunityKind.morningMist => '晨雾窗口',
    PhotographyOpportunityKind.sunsetGlow => '晚霞窗口',
    PhotographyOpportunityKind.astronomy => '天象窗口',
  };
}
