import 'dart:convert';

import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);

class PersistentContextCache implements ContextCache {
  PersistentContextCache(
    this._preferences, {
    this.storageKey = 'environment_context_snapshot_v1',
  });

  // Version 7 adds server-derived moon and Galactic-centre geometry. Older
  // cache values are discarded so missing evidence cannot look current.
  static const _version = 7;
  final SharedPreferencesAsync _preferences;
  final String storageKey;

  /// Serializes read-modify-write operations within this instance so that
  /// concurrent writes cannot reorder during async SharedPreferences calls.
  /// A failed write is caught so the chain continues for subsequent callers.
  Future<void> _writeChain = Future<void>.value();

  @override
  Future<ContextSnapshot?> readLatest() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw);
      if (body is! Map || body['version'] != _version) {
        return null;
      }
      return _decodeSnapshot(body['snapshot']);
    } on Object {
      // Cached context is optional recovery data. Corruption, a partial write
      // or an incompatible schema must never prevent the live app starting.
      return null;
    }
  }

  @override
  Future<void> write(ContextSnapshot snapshot) {
    return _enqueue(() => _writeGuarded(snapshot));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writeChain.then((_) => operation());
    // Chain the next write after this one settles, regardless of success.
    // A single failure must not poison the queue for later callers.
    _writeChain = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _writeGuarded(ContextSnapshot snapshot) async {
    final latest = await readLatest();
    if (latest != null && !canReplaceCachedSnapshot(snapshot, latest)) return;
    await _preferences.setString(
      storageKey,
      jsonEncode({'version': _version, 'snapshot': _encodeSnapshot(snapshot)}),
    );
  }

  @override
  Future<void> clear() => _enqueue(() async {
    await _preferences.remove(storageKey);
  });

  Map<String, Object?> _encodeSnapshot(ContextSnapshot value) => {
    'id': value.id,
    'observedAt': value.observedAt.toUtc().toIso8601String(),
    'expiresAt': value.expiresAt.toUtc().toIso8601String(),
    'primaryScene': value.primaryScene.name,
    'sceneContext': _encodeSceneContext(value.resolvedSceneContext),
    'opportunityCatalogVersion': OpportunityCatalog.current.version,
    'dayPhase': value.dayPhase.name,
    'weather': value.weather.name,
    'activeRoute': value.activeRoute,
    'opportunityIds': value.opportunityIds,
    'safetyEventIds': value.safetyEventIds,
    'wildlifeEventIds': value.wildlifeEventIds,
    'events': value.events.map(_encodeEvent).toList(),
    'shootingSessions':
        value.isStale || value.dataFreshness == ContextDataFreshness.stale
        ? const <Object?>[]
        : value.shootingSessions.map(_encodeShootingSession).toList(),
    'wildlifeActivity': value.wildlifeActivity == null
        ? null
        : _encodeWildlife(value.wildlifeActivity!),
    'location': value.location == null ? null : _encodePoint(value.location!),
    'temperatureCelsius': value.temperatureCelsius,
    'windSpeedMetersPerSecond': value.windSpeedMetersPerSecond,
    'windDirectionDegrees': value.windDirectionDegrees,
    'visibilityKilometers': value.visibilityKilometers,
    'precipitationMillimeters': value.precipitationMillimeters,
    'cloudCoverPercent': value.cloudCoverPercent,
    'airQualityIndex': value.airQualityIndex,
    'airQualityCategory': value.airQualityCategory,
    'primaryPollutant': value.primaryPollutant,
    'airQualityObservedAt': value.airQualityObservedAt
        ?.toUtc()
        .toIso8601String(),
    'airQualityStale': value.airQualityStale,
    'solarElevationDegrees': value.solarElevationDegrees,
    'solarAzimuthDegrees': value.solarAzimuthDegrees,
    'sunrise': value.sunrise?.toUtc().toIso8601String(),
    'sunset': value.sunset?.toUtc().toIso8601String(),
    'isStale': value.isStale,
    'remoteGeneratedAt': value.remoteGeneratedAt?.toUtc().toIso8601String(),
    'dataFreshness': value.dataFreshness.name,
    'moonPhase': value.moonPhase?.name,
    'moonIllumination': value.moonIllumination,
    'astronomyGeometry': value.astronomyGeometry == null
        ? null
        : _encodeAstronomy(value.astronomyGeometry!),
    'routeMode': value.routeMode.name,
    'routeStage': value.routeStage.name,
    'allowedActions': value.allowedActions.map((value) => value.name).toList(),
    'canonicalEntriesPresent': value.canonicalEntriesPresent,
  };

  ContextSnapshot? _decodeSnapshot(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final observedAt = _date(raw['observedAt']);
    final expiresAt = _date(raw['expiresAt']);
    final scene = _enumByName(SceneType.values, raw['primaryScene']);
    final phase = _enumByName(DayPhase.values, raw['dayPhase']);
    final weather = _enumByName(WeatherType.values, raw['weather']);
    final activeRoute = raw['activeRoute'];
    final dataFreshness = _enumByName(
      ContextDataFreshness.values,
      raw['dataFreshness'],
    );
    final routeMode = _enumByName(ContextRouteMode.values, raw['routeMode']);
    final routeStage = _enumByName(ContextRouteStage.values, raw['routeStage']);
    if (id is! String ||
        observedAt == null ||
        expiresAt == null ||
        scene == null ||
        phase == null ||
        weather == null ||
        activeRoute is! bool ||
        dataFreshness == null ||
        routeMode == null ||
        routeStage == null) {
      return null;
    }
    final events = _list(
      raw['events'],
    ).map(_decodeEvent).whereType<ContextEvent>();
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: scene,
      sceneContext: _decodeSceneContext(raw['sceneContext']),
      dayPhase: phase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: _stringList(raw['opportunityIds']),
      safetyEventIds: _stringList(raw['safetyEventIds']),
      wildlifeEventIds: _stringList(raw['wildlifeEventIds']),
      events: events.toList(growable: false),
      shootingSessions:
          raw['isStale'] == true || dataFreshness == ContextDataFreshness.stale
          ? const []
          : _decodeShootingSessions(raw['shootingSessions']),
      wildlifeActivity: _decodeWildlife(raw['wildlifeActivity']),
      location: _decodePoint(raw['location']),
      temperatureCelsius: _double(raw['temperatureCelsius']),
      windSpeedMetersPerSecond: _double(raw['windSpeedMetersPerSecond']),
      windDirectionDegrees: _double(raw['windDirectionDegrees']),
      visibilityKilometers: _double(raw['visibilityKilometers']),
      precipitationMillimeters: _double(raw['precipitationMillimeters']),
      cloudCoverPercent: _double(raw['cloudCoverPercent']),
      airQualityIndex: raw['airQualityIndex'] is int
          ? raw['airQualityIndex'] as int
          : null,
      airQualityCategory: raw['airQualityCategory'] is String
          ? raw['airQualityCategory'] as String
          : null,
      primaryPollutant: raw['primaryPollutant'] is String
          ? raw['primaryPollutant'] as String
          : null,
      airQualityObservedAt: _date(raw['airQualityObservedAt']),
      airQualityStale: raw['airQualityStale'] != false,
      solarElevationDegrees: _double(raw['solarElevationDegrees']),
      solarAzimuthDegrees: _double(raw['solarAzimuthDegrees']),
      sunrise: _date(raw['sunrise']),
      sunset: _date(raw['sunset']),
      isStale: raw['isStale'] == true,
      remoteGeneratedAt: _date(raw['remoteGeneratedAt']),
      dataFreshness: dataFreshness,
      moonPhase: _enumByName(MoonPhase.values, raw['moonPhase']),
      moonIllumination: _double(raw['moonIllumination']),
      astronomyGeometry: _decodeAstronomy(raw['astronomyGeometry']),
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: _enumList(ContextAction.values, raw['allowedActions']),
      canonicalEntriesPresent: raw['canonicalEntriesPresent'] == true,
    );
  }

  Map<String, Object?> _encodeSceneContext(SceneContext value) => {
    'primaryScene': value.primaryScene.name,
    'facets': value.facets.map((item) => item.name).toList(growable: false),
    'activity': value.activity.name,
    'scores': {
      for (final entry in value.scores.entries) entry.key.name: entry.value,
    },
    'reviewedOverride': value.reviewedOverride,
  };

  Map<String, Object?> _encodeAstronomy(AstronomyGeometry value) => {
    'status': value.status.name,
    'astronomicalNight': value.astronomicalNight,
    'moonAltitudeDegrees': value.moonAltitudeDegrees,
    'moonAzimuthDegrees': value.moonAzimuthDegrees,
    'moonriseAt': value.moonriseAt?.toUtc().toIso8601String(),
    'moonsetAt': value.moonsetAt?.toUtc().toIso8601String(),
    'moonPhase': value.moonPhase?.name,
    'moonIllumination': value.moonIllumination,
    'galacticCenterAltitudeDegrees': value.galacticCenterAltitudeDegrees,
    'galacticCenterAzimuthDegrees': value.galacticCenterAzimuthDegrees,
    'galacticCenterWindow': value.galacticCenterWindow == null
        ? null
        : {
            'startAt': value.galacticCenterWindow!.startAt
                .toUtc()
                .toIso8601String(),
            'peakAt': value.galacticCenterWindow!.peakAt
                .toUtc()
                .toIso8601String(),
            'endAt': value.galacticCenterWindow!.endAt
                .toUtc()
                .toIso8601String(),
            'peakAltitudeDegrees':
                value.galacticCenterWindow!.peakAltitudeDegrees,
          },
  };

  AstronomyGeometry? _decodeAstronomy(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map ||
        !_hasExactKeys(raw, const {
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
    final status = _enumByName(AstronomyGeometryStatus.values, raw['status']);
    if (status == null) return null;
    final moonPhase = _enumByName(MoonPhase.values, raw['moonPhase']);
    final astronomicalNight = raw['astronomicalNight'];
    final moonAltitude = _double(raw['moonAltitudeDegrees']);
    final moonAzimuth = _double(raw['moonAzimuthDegrees']);
    final moonIllumination = _double(raw['moonIllumination']);
    final galacticAltitude = _double(raw['galacticCenterAltitudeDegrees']);
    final galacticAzimuth = _double(raw['galacticCenterAzimuthDegrees']);
    final window = _decodeGalacticWindow(raw['galacticCenterWindow']);
    final moonrise = _date(raw['moonriseAt']);
    final moonset = _date(raw['moonsetAt']);
    if (status == AstronomyGeometryStatus.geometryOnly &&
        (astronomicalNight is! bool ||
            moonPhase == null ||
            !_inRange(moonAltitude, -90, 90) ||
            !_inRange(moonAzimuth, 0, 360, upperExclusive: true) ||
            !_inRange(moonIllumination, 0, 1) ||
            !_inRange(galacticAltitude, -90, 90) ||
            !_inRange(galacticAzimuth, 0, 360, upperExclusive: true) ||
            (raw['moonriseAt'] != null && moonrise == null) ||
            (raw['moonsetAt'] != null && moonset == null) ||
            (raw['galacticCenterWindow'] != null && window == null))) {
      return null;
    }
    if (status == AstronomyGeometryStatus.unavailable &&
        (astronomicalNight != null ||
            moonPhase != null ||
            moonAltitude != null ||
            moonAzimuth != null ||
            moonIllumination != null ||
            galacticAltitude != null ||
            galacticAzimuth != null ||
            raw['moonriseAt'] != null ||
            raw['moonsetAt'] != null ||
            raw['galacticCenterWindow'] != null)) {
      return null;
    }
    return AstronomyGeometry(
      status: status,
      astronomicalNight: astronomicalNight as bool?,
      moonAltitudeDegrees: moonAltitude,
      moonAzimuthDegrees: moonAzimuth,
      moonriseAt: moonrise,
      moonsetAt: moonset,
      moonPhase: moonPhase,
      moonIllumination: moonIllumination,
      galacticCenterAltitudeDegrees: galacticAltitude,
      galacticCenterAzimuthDegrees: galacticAzimuth,
      galacticCenterWindow: window,
    );
  }

  GalacticCenterWindow? _decodeGalacticWindow(Object? raw) {
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
    final start = _date(raw['startAt']);
    final peak = _date(raw['peakAt']);
    final end = _date(raw['endAt']);
    final altitude = _double(raw['peakAltitudeDegrees']);
    if (start == null ||
        peak == null ||
        end == null ||
        peak.isBefore(start) ||
        peak.isAfter(end) ||
        !_inRange(altitude, 10, 90)) {
      return null;
    }
    return GalacticCenterWindow(
      startAt: start,
      peakAt: peak,
      endAt: end,
      peakAltitudeDegrees: altitude!,
    );
  }

  bool _inRange(
    double? value,
    double minimum,
    double maximum, {
    bool upperExclusive = false,
  }) =>
      value != null &&
      value.isFinite &&
      value >= minimum &&
      (upperExclusive ? value < maximum : value <= maximum);

  SceneContext? _decodeSceneContext(Object? raw) {
    if (raw == null) return null;
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
    final primary = _enumByName(PrimaryScene.values, raw['primaryScene']);
    final activity = _enumByName(ActivityState.values, raw['activity']);
    final facets = _enumList(SceneFacet.values, raw['facets']);
    final rawScores = raw['scores'];
    if (primary == null ||
        activity == null ||
        rawScores is! Map ||
        raw['reviewedOverride'] is! bool) {
      return null;
    }
    final scores = <PrimaryScene, int>{};
    for (final entry in rawScores.entries) {
      final scene = _enumByName(PrimaryScene.values, entry.key);
      if (scene == null || entry.value is! int) return null;
      scores[scene] = entry.value! as int;
    }
    return SceneContext(
      primaryScene: primary,
      facets: facets,
      activity: activity,
      scores: scores,
      reviewedOverride: raw['reviewedOverride']! as bool,
    );
  }

  Map<String, Object?> _encodeShootingSession(ShootingSession value) => {
    'id': value.id,
    'kind': value.kind.name,
    'title': value.title,
    'startsAt': value.startsAt.toUtc().toIso8601String(),
    'endsAt': value.endsAt.toUtc().toIso8601String(),
    'primaryPhase': value.primaryPhase.name,
    'conditionBand': value.conditionBand.name,
    'confidenceBand': value.confidenceBand.name,
    'trend': value.trend.name,
    'phases': value.phases
        .map(
          (phase) => {
            'kind': phase.kind.name,
            'startsAt': phase.startsAt.toUtc().toIso8601String(),
            'peaksAt': phase.peaksAt.toUtc().toIso8601String(),
            'endsAt': phase.endsAt.toUtc().toIso8601String(),
            'conditionBand': phase.conditionBand.name,
            'directionDegrees': phase.directionDegrees,
          },
        )
        .toList(),
    'factors': value.factors
        .map(
          (factor) => {
            'id': factor.id,
            'effect': factor.effect.name,
            'label': factor.label,
            'value': factor.value,
            'sourceAt': factor.sourceAt.toUtc().toIso8601String(),
          },
        )
        .toList(),
    'trendSamples': value.trendSamples
        .map(
          (sample) => {
            'at': sample.at.toUtc().toIso8601String(),
            'conditionIndex': sample.conditionIndex,
            'cloudCoverPercent': sample.cloudCoverPercent,
            'windSpeedMps': sample.windSpeedMps,
            'precipitationMm': sample.precipitationMm,
          },
        )
        .toList(),
    'targetCandidates': value.targetCandidates
        .map(
          (target) => {
            'id': target.id,
            'name': target.name,
            'coordinate': _encodePoint(target.coordinate),
            'supportedSessions': target.supportedSessions
                .map((item) => item.name)
                .toList(),
            'viewBearingDegrees': target.viewBearingDegrees,
            'bearingToleranceDegrees': target.bearingToleranceDegrees,
            'accessModes': target.accessModes.map((item) => item.name).toList(),
            'leadTimeMinutes': target.leadTimeMinutes,
            'arrivalRadiusMeters': target.arrivalRadiusMeters,
            'shorelineSide': target.shorelineSide.name,
            'reviewedAt': target.reviewedAt.toUtc().toIso8601String(),
            'reviewReference': target.reviewReference.toString(),
            'sourceAttribution': target.sourceAttribution,
            'sourceLicense': target.sourceLicense,
            'sourceUrl': target.sourceUrl.toString(),
          },
        )
        .toList(),
    'recommendedCapabilities': value.recommendedCapabilities
        .map((capability) => capability.id)
        .toList(),
    'ruleVersion': value.ruleVersion,
    'expiresAt': value.expiresAt.toUtc().toIso8601String(),
  };

  List<ShootingSession> _decodeShootingSessions(Object? raw) {
    if (raw is! List || raw.length > 2) return const [];
    try {
      return List.unmodifiable(
        raw.map((entry) {
          if (entry is! Map) throw const FormatException();
          final item = Map<String, Object?>.from(entry);
          final phases = _list(item['phases']).map((entry) {
            if (entry is! Map) throw const FormatException();
            final value = Map<String, Object?>.from(entry);
            return ShootingSessionPhase(
              kind: _enumByName(ShootingPhaseKind.values, value['kind'])!,
              startsAt: _date(value['startsAt'])!,
              peaksAt: _date(value['peaksAt'])!,
              endsAt: _date(value['endsAt'])!,
              conditionBand: _enumByName(
                ShootingConditionBand.values,
                value['conditionBand'],
              )!,
              directionDegrees: _double(value['directionDegrees'])!,
            );
          }).toList();
          final factors = _list(item['factors']).map((entry) {
            if (entry is! Map) throw const FormatException();
            final value = Map<String, Object?>.from(entry);
            return ShootingSessionFactor(
              id: value['id']! as String,
              effect: _enumByName(
                ShootingFactorEffect.values,
                value['effect'],
              )!,
              label: value['label']! as String,
              value: value['value']! as String,
              sourceAt: _date(value['sourceAt'])!,
            );
          }).toList();
          final samples = _list(item['trendSamples']).map((entry) {
            if (entry is! Map) throw const FormatException();
            final value = Map<String, Object?>.from(entry);
            return ShootingSessionTrendSample(
              at: _date(value['at'])!,
              conditionIndex: value['conditionIndex']! as int,
              cloudCoverPercent: _double(value['cloudCoverPercent']),
              windSpeedMps: _double(value['windSpeedMps'])!,
              precipitationMm: _double(value['precipitationMm'])!,
            );
          }).toList();
          final targets = _list(item['targetCandidates']).map((entry) {
            if (entry is! Map) throw const FormatException();
            final value = Map<String, Object?>.from(entry);
            return ShootingTarget(
              id: value['id']! as String,
              name: value['name']! as String,
              coordinate: _decodePoint(value['coordinate'])!,
              supportedSessions: _enumList(
                ShootingSessionKind.values,
                value['supportedSessions'],
              ),
              viewBearingDegrees: _double(value['viewBearingDegrees'])!,
              bearingToleranceDegrees: _double(
                value['bearingToleranceDegrees'],
              )!,
              accessModes: _enumList(
                ShootingTravelMode.values,
                value['accessModes'],
              ),
              leadTimeMinutes: value['leadTimeMinutes']! as int,
              arrivalRadiusMeters: value['arrivalRadiusMeters']! as int,
              shorelineSide: _enumByName(
                ShootingShorelineSide.values,
                value['shorelineSide'],
              )!,
              reviewedAt: _date(value['reviewedAt'])!,
              reviewReference: Uri.parse(value['reviewReference']! as String),
              sourceAttribution: value['sourceAttribution']! as String,
              sourceLicense: value['sourceLicense']! as String,
              sourceUrl: Uri.parse(value['sourceUrl']! as String),
            );
          }).toList();
          final capabilities = _list(item['recommendedCapabilities']).map((
            entry,
          ) {
            if (entry is! String) throw const FormatException();
            return EquipmentCapability.values
                .where((capability) => capability.id == entry)
                .firstOrNull;
          }).toList();
          if (capabilities.any((capability) => capability == null)) {
            throw const FormatException();
          }
          return ShootingSession(
            id: item['id']! as String,
            kind: _enumByName(ShootingSessionKind.values, item['kind'])!,
            title: item['title']! as String,
            startsAt: _date(item['startsAt'])!,
            endsAt: _date(item['endsAt'])!,
            primaryPhase: _enumByName(
              ShootingPhaseKind.values,
              item['primaryPhase'],
            )!,
            conditionBand: _enumByName(
              ShootingConditionBand.values,
              item['conditionBand'],
            )!,
            confidenceBand: _enumByName(
              ShootingConfidenceBand.values,
              item['confidenceBand'],
            )!,
            trend: _enumByName(ShootingTrend.values, item['trend'])!,
            phases: phases,
            factors: factors,
            trendSamples: samples,
            targetCandidates: targets,
            recommendedCapabilities: capabilities.cast<EquipmentCapability>(),
            ruleVersion: item['ruleVersion']! as String,
            expiresAt: _date(item['expiresAt'])!,
          );
        }),
      );
    } on Object {
      return const [];
    }
  }

  Map<String, Object?> _encodeEvent(ContextEvent event) => {
    'id': event.id,
    'channel': event.channel.name,
    'source': event.source.name,
    'observedAt': event.observedAt.toUtc().toIso8601String(),
    'expiresAt': event.expiresAt.toUtc().toIso8601String(),
    'confidence': event.confidence,
    'geoScope': event.geoScope?.name,
    'safetyLevel': event.safetyLevel?.name,
    'allowedAction': event.allowedAction?.name,
    'title': event.title,
    'sourceUrl': event.sourceUri?.toString(),
  };

  ContextEvent? _decodeEvent(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final channel = _enumByName(ContextEventChannel.values, raw['channel']);
    final source = _enumByName(ContextEventSource.values, raw['source']);
    final observedAt = _date(raw['observedAt']);
    final expiresAt = _date(raw['expiresAt']);
    final confidence = _double(raw['confidence']);
    final action = _enumByName(ContextAction.values, raw['allowedAction']);
    final rawTitle = raw['title'];
    final rawSourceUrl = raw['sourceUrl'];
    final sourceUri = rawSourceUrl is String
        ? Uri.tryParse(rawSourceUrl)
        : null;
    if (id is! String ||
        channel == null ||
        source == null ||
        observedAt == null ||
        expiresAt == null ||
        confidence == null ||
        confidence < 0 ||
        confidence > 1 ||
        (rawTitle != null &&
            (rawTitle is! String ||
                rawTitle.trim().isEmpty ||
                rawTitle.runes.length > 80)) ||
        (rawSourceUrl != null &&
            (sourceUri == null ||
                sourceUri.scheme != 'https' ||
                sourceUri.host.isEmpty)) ||
        (action == ContextAction.openAstronomyDetail &&
            (source != ContextEventSource.astronomyCatalog ||
                rawTitle is! String ||
                sourceUri == null)) ||
        (action != ContextAction.openAstronomyDetail && rawSourceUrl != null)) {
      return null;
    }
    return ContextEvent(
      id: id,
      channel: channel,
      source: source,
      observedAt: observedAt,
      expiresAt: expiresAt,
      confidence: confidence,
      geoScope: _enumByName(ContextGeoScope.values, raw['geoScope']),
      safetyLevel: _enumByName(ContextSafetyLevel.values, raw['safetyLevel']),
      allowedAction: action,
      title: raw['title'] is String ? raw['title'] as String : null,
      sourceUri: sourceUri,
    );
  }

  Map<String, Object?> _encodePoint(GeoPoint point) => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    'coordinateSystem': point.coordinateSystem.name,
  };

  GeoPoint? _decodePoint(Object? raw) {
    if (raw is! Map) return null;
    final latitude = _double(raw['latitude']);
    final longitude = _double(raw['longitude']);
    final system = _enumByName(
      CoordinateSystem.values,
      raw['coordinateSystem'],
    );
    if (latitude == null ||
        longitude == null ||
        system == null ||
        system == CoordinateSystem.unknown) {
      return null;
    }
    return GeoPoint(
      latitude: latitude,
      longitude: longitude,
      coordinateSystem: system,
    ).validate();
  }

  Map<String, Object?> _encodeWildlife(RegionalWildlifeActivity activity) => {
    'contractVersion': activity.contractVersion,
    'radiusKilometers': activity.radiusKilometers,
    'occurrenceSampleSize': activity.occurrenceSampleSize,
    'scannedOccurrenceSampleSize': activity.scannedOccurrenceSampleSize,
    'eligibleOccurrenceSampleSize': activity.eligibleOccurrenceSampleSize,
    'datasetReferencesTruncated': activity.datasetReferencesTruncated,
    'qualityPolicy': activity.qualityPolicy == null
        ? null
        : {
            'acceptedLicenses': activity.qualityPolicy!.acceptedLicenses,
            'acceptedBasisOfRecord':
                activity.qualityPolicy!.acceptedBasisOfRecord,
            'maximumCoordinateUncertaintyMeters':
                activity.qualityPolicy!.maximumCoordinateUncertaintyMeters,
            'maximumDatasetReferences':
                activity.qualityPolicy!.maximumDatasetReferences,
            'excludesSevereGeospatialIssues':
                activity.qualityPolicy!.excludesSevereGeospatialIssues,
          },
    'historicalRecordConcentration':
        activity.historicalRecordConcentration == null
        ? null
        : {
            'recordsWithMonth':
                activity.historicalRecordConcentration!.recordsWithMonth,
            'recordsWithTime':
                activity.historicalRecordConcentration!.recordsWithTime,
            'months': activity.historicalRecordConcentration!.months
                .map(
                  (entry) => {'month': entry.month, 'records': entry.records},
                )
                .toList(),
            'timePeriods': activity.historicalRecordConcentration!.timePeriods
                .map(
                  (entry) => {
                    'period': entry.period.name,
                    'records': entry.records,
                  },
                )
                .toList(),
          },
    'datasets': activity.datasets
        .map(
          (dataset) => {
            'datasetKey': dataset.datasetKey,
            'title': dataset.title,
            'publisher': dataset.publisher,
            'licenses': dataset.licenses,
            'records': dataset.records,
            'citation': dataset.citation,
            'url': dataset.url.toString(),
          },
        )
        .toList(),
    'taxa': activity.taxa
        .map(
          (taxon) => {
            'scientificName': taxon.scientificName,
            'commonName': taxon.commonName,
            'group': taxon.group.name,
            'records': taxon.records,
          },
        )
        .toList(),
  };

  RegionalWildlifeActivity? _decodeWildlife(Object? raw) {
    if (raw is! Map) return null;
    final radius = raw['radiusKilometers'];
    final sampleSize = raw['occurrenceSampleSize'];
    if (radius is! int || sampleSize is! int) return null;
    final contractVersion = raw['contractVersion'] is int
        ? raw['contractVersion'] as int
        : 1;
    final scannedSampleSize = raw['scannedOccurrenceSampleSize'] is int
        ? raw['scannedOccurrenceSampleSize'] as int
        : 0;
    final eligibleSampleSize = raw['eligibleOccurrenceSampleSize'] is int
        ? raw['eligibleOccurrenceSampleSize'] as int
        : 0;
    final datasetReferencesTruncated = raw['datasetReferencesTruncated'] is bool
        ? raw['datasetReferencesTruncated'] as bool
        : false;
    final taxa = _list(raw['taxa']).map((value) {
      if (value is! Map) return null;
      final scientificName = value['scientificName'];
      final group = _enumByName(WildlifeGroup.values, value['group']);
      final records = value['records'];
      final commonName = value['commonName'];
      if (scientificName is! String || group == null || records is! int) {
        return null;
      }
      return WildlifeTaxon(
        scientificName: scientificName,
        commonName: commonName is String ? commonName : null,
        group: group,
        records: records,
      );
    }).whereType<WildlifeTaxon>();
    return RegionalWildlifeActivity(
      contractVersion: contractVersion,
      radiusKilometers: radius,
      occurrenceSampleSize: sampleSize,
      scannedOccurrenceSampleSize: scannedSampleSize,
      eligibleOccurrenceSampleSize: eligibleSampleSize,
      datasetReferencesTruncated: datasetReferencesTruncated,
      qualityPolicy: _decodeWildlifeQualityPolicy(raw['qualityPolicy']),
      historicalRecordConcentration: _decodeWildlifeConcentration(
        raw['historicalRecordConcentration'],
      ),
      datasets: _decodeWildlifeDatasets(raw['datasets']),
      taxa: taxa.toList(growable: false),
    );
  }

  WildlifeQualityPolicy? _decodeWildlifeQualityPolicy(Object? raw) {
    if (raw is! Map ||
        raw['acceptedLicenses'] is! List ||
        raw['acceptedBasisOfRecord'] is! List ||
        raw['maximumCoordinateUncertaintyMeters'] is! int ||
        raw['maximumDatasetReferences'] is! int ||
        raw['excludesSevereGeospatialIssues'] is! bool) {
      return null;
    }
    return WildlifeQualityPolicy(
      acceptedLicenses: _list(
        raw['acceptedLicenses'],
      ).whereType<String>().toList(),
      acceptedBasisOfRecord: _list(
        raw['acceptedBasisOfRecord'],
      ).whereType<String>().toList(),
      maximumCoordinateUncertaintyMeters:
          raw['maximumCoordinateUncertaintyMeters'] as int,
      maximumDatasetReferences: raw['maximumDatasetReferences'] as int,
      excludesSevereGeospatialIssues:
          raw['excludesSevereGeospatialIssues'] as bool,
    );
  }

  WildlifeHistoricalRecordConcentration? _decodeWildlifeConcentration(
    Object? raw,
  ) {
    if (raw is! Map ||
        raw['recordsWithMonth'] is! int ||
        raw['recordsWithTime'] is! int) {
      return null;
    }
    final months = _list(raw['months'])
        .map((entry) {
          if (entry is! Map ||
              entry['month'] is! int ||
              entry['records'] is! int) {
            return null;
          }
          return WildlifeMonthConcentration(
            month: entry['month'] as int,
            records: entry['records'] as int,
          );
        })
        .whereType<WildlifeMonthConcentration>()
        .toList();
    final periods = _list(raw['timePeriods'])
        .map((entry) {
          if (entry is! Map || entry['records'] is! int) return null;
          final period = _enumByName(
            WildlifeObservationPeriod.values,
            entry['period'],
          );
          if (period == null) return null;
          return WildlifePeriodConcentration(
            period: period,
            records: entry['records'] as int,
          );
        })
        .whereType<WildlifePeriodConcentration>()
        .toList();
    return WildlifeHistoricalRecordConcentration(
      recordsWithMonth: raw['recordsWithMonth'] as int,
      recordsWithTime: raw['recordsWithTime'] as int,
      months: months,
      timePeriods: periods,
    );
  }

  List<WildlifeDatasetReference> _decodeWildlifeDatasets(Object? raw) =>
      _list(raw)
          .map((entry) {
            if (entry is! Map ||
                entry['datasetKey'] is! String ||
                entry['title'] is! String ||
                entry['publisher'] is! String ||
                entry['licenses'] is! List ||
                entry['records'] is! int ||
                entry['citation'] is! String ||
                entry['url'] is! String) {
              return null;
            }
            final url = Uri.tryParse(entry['url'] as String);
            if (url == null || url.scheme != 'https') return null;
            return WildlifeDatasetReference(
              datasetKey: entry['datasetKey'] as String,
              title: entry['title'] as String,
              publisher: entry['publisher'] as String,
              licenses: _list(entry['licenses']).whereType<String>().toList(),
              records: entry['records'] as int,
              citation: entry['citation'] as String,
              url: url,
            );
          })
          .whereType<WildlifeDatasetReference>()
          .toList(growable: false);

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static List<String> _stringList(Object? value) =>
      _list(value).whereType<String>().toList(growable: false);

  static List<T> _enumList<T extends Enum>(List<T> values, Object? raw) =>
      _list(raw)
          .map((value) => _enumByName(values, value))
          .whereType<T>()
          .toList(growable: false);

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
