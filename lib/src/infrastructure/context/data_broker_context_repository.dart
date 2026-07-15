import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/remote_context_repository.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

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
};

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> keys) {
  return value.length == keys.length && value.keys.every(keys.contains);
}

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
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final ContextDataTransport transport;

  @override
  Future<ContextSnapshot> fetchSnapshot({
    required LocationReading location,
    required DateTime observedAt,
    RouteContextState route = RouteContextState.none,
  }) {
    return _post(
      request: _canonicalRequest(location, observedAt, route),
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
    try {
      final body = await transport.post(
        uri,
        headers: {'Authorization': 'Bearer $serviceToken'},
        body: request,
      );
      return _parse(body, location: location, fallback: fallback);
    } on RemoteContextFailure {
      rethrow;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400) {
        throw const RemoteContextFailure(
          RemoteContextFailureKind.unsupportedContract,
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
  ) {
    return {
      'contractVersion': 2,
      'coordinate': {
        'latitude': location.point.latitude,
        'longitude': location.point.longitude,
        'system': 'wgs84',
      },
      'observedAt': observedAt.toUtc().toIso8601String(),
      'locale': 'zh-CN',
      'intent': 'photography',
      'route': route.toRequest(),
    };
  }

  Map<String, Object?> _legacyRequest(
    ContextSnapshot base,
    WeatherObservation weather,
    SolarState solar,
  ) {
    final scene = base.primaryScene;
    return {
      'contractVersion': 2,
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
    if (!_hasExactKeys(body, _responseKeys) ||
        body['contractVersion'] != 2 ||
        body['contextId'] is! String ||
        body['scene'] is! String ||
        body['events'] is! List ||
        body['dataFreshness'] is! Map ||
        body['weather'] is! Map ||
        body['sunMoon'] is! Map ||
        body['route'] is! Map ||
        body['manifest'] is! Map ||
        body['allowedActions'] is! List) {
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
    final primaryEventId = manifest['primaryEventId']! as String?;
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
      wildlifeActivity: fallback?.wildlifeActivity,
      location: location,
      temperatureCelsius: (temperature as num?)?.toDouble(),
      windSpeedMetersPerSecond: (windSpeed! as num).toDouble(),
      windDirectionDegrees: (windDirection as num?)?.toDouble(),
      visibilityKilometers: (visibility! as num).toDouble(),
      precipitationMillimeters: (precipitation! as num).toDouble(),
      cloudCoverPercent: (cloudCover as num?)?.toDouble(),
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
    if (!_hasExactKeys(value, const {
          'id',
          'channel',
          'source',
          'observedAt',
          'expiresAt',
          'confidence',
          'geoScope',
          'severity',
          'allowedAction',
        }) ||
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
        action == null) {
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
    );
  }
}
