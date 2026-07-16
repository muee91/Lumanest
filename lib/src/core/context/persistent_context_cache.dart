import 'dart:convert';

import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _hasExactKeys(Map<Object?, Object?> value, Set<String> keys) =>
    value.length == keys.length && value.keys.every(keys.contains);

class PersistentContextCache implements ContextCache {
  PersistentContextCache(
    this._preferences, {
    this.storageKey = 'environment_context_snapshot_v1',
  });

  static const _version = 3;
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
      if (body is! Map ||
          (body['version'] != 2 && body['version'] != _version)) {
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
    'dayPhase': value.dayPhase.name,
    'weather': value.weather.name,
    'activeRoute': value.activeRoute,
    'opportunityIds': value.opportunityIds,
    'safetyEventIds': value.safetyEventIds,
    'wildlifeEventIds': value.wildlifeEventIds,
    'events': value.events.map(_encodeEvent).toList(),
    'photographyOpportunities':
        value.isStale || value.dataFreshness == ContextDataFreshness.stale
        ? const <Object?>[]
        : value.photographyOpportunities
              .map(_encodePhotographyOpportunity)
              .toList(growable: false),
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
    'routeMode': value.routeMode.name,
    'routeStage': value.routeStage.name,
    'allowedActions': value.allowedActions.map((value) => value.name).toList(),
    if (value.serverManifest != null)
      'serverManifest': _encodeManifest(value.serverManifest!),
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
    final manifest = _decodeManifest(raw['serverManifest']);
    if (identical(manifest, _manifestDecodeFailure)) return null;
    return ContextSnapshot(
      id: id,
      observedAt: observedAt,
      expiresAt: expiresAt,
      primaryScene: scene,
      dayPhase: phase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: _stringList(raw['opportunityIds']),
      safetyEventIds: _stringList(raw['safetyEventIds']),
      wildlifeEventIds: _stringList(raw['wildlifeEventIds']),
      events: events.toList(growable: false),
      photographyOpportunities:
          raw['isStale'] == true || dataFreshness == ContextDataFreshness.stale
          ? const []
          : _decodePhotographyOpportunities(raw['photographyOpportunities']),
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
      routeMode: routeMode,
      routeStage: routeStage,
      allowedActions: _enumList(ContextAction.values, raw['allowedActions']),
      serverManifest: manifest as ServerManifest?,
    );
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

  Map<String, Object?> _encodePhotographyOpportunity(
    PhotographyOpportunity opportunity,
  ) => {
    'id': opportunity.id,
    'kind': opportunity.kind.name,
    'title': opportunity.title,
    'startsAt': opportunity.startsAt.toUtc().toIso8601String(),
    'peaksAt': opportunity.peaksAt.toUtc().toIso8601String(),
    'expiresAt': opportunity.expiresAt.toUtc().toIso8601String(),
    'score': opportunity.score,
    'confidence': opportunity.confidence,
    'geoScope': opportunity.geoScope.name,
    'directionDegrees': opportunity.directionDegrees,
    'primaryAction': opportunity.primaryAction?.name,
    'fallbackAction': opportunity.fallbackAction?.name,
    'equipmentHints': opportunity.equipmentHints,
    'evidence': opportunity.evidence
        .map(
          (item) => {
            'id': item.id,
            'kind': item.kind.name,
            'statement': item.statement,
            'confidence': item.confidence,
            'supports': item.supports,
          },
        )
        .toList(growable: false),
  };

  List<PhotographyOpportunity> _decodePhotographyOpportunities(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List || raw.length > 8) return const [];
    final opportunities = <PhotographyOpportunity>[];
    final ids = <String>{};
    for (final value in raw) {
      if (value is! Map) return const [];
      final item = Map<String, Object?>.from(value);
      const keys = {
        'id',
        'kind',
        'title',
        'startsAt',
        'peaksAt',
        'expiresAt',
        'score',
        'confidence',
        'geoScope',
        'directionDegrees',
        'primaryAction',
        'fallbackAction',
        'equipmentHints',
        'evidence',
      };
      final id = item['id'];
      final kind = _enumByName(PhotographyOpportunityKind.values, item['kind']);
      final scope = _enumByName(
        PhotographyOpportunityGeoScope.values,
        item['geoScope'],
      );
      final startsAt = _date(item['startsAt']);
      final peaksAt = _date(item['peaksAt']);
      final expiresAt = _date(item['expiresAt']);
      final score = item['score'];
      final confidence = _double(item['confidence']);
      final direction = item['directionDegrees'];
      final primaryAction = item['primaryAction'] == null
          ? null
          : _enumByName(ContextAction.values, item['primaryAction']);
      final fallbackAction = item['fallbackAction'] == null
          ? null
          : _enumByName(ContextAction.values, item['fallbackAction']);
      final evidence = _decodePhotographyEvidence(item['evidence']);
      final hints = item['equipmentHints'];
      if (!_hasExactKeys(item, keys) ||
          id is! String ||
          !RegExp(r'^photo-[a-z0-9_-]{1,58}$').hasMatch(id) ||
          item['title'] is! String ||
          (item['title'] as String).trim().isEmpty ||
          (item['title'] as String).runes.length > 80 ||
          kind == null ||
          scope == null ||
          startsAt == null ||
          peaksAt == null ||
          expiresAt == null ||
          peaksAt.isBefore(startsAt) ||
          expiresAt.isBefore(peaksAt) ||
          score is! int ||
          score < 0 ||
          score > 100 ||
          confidence == null ||
          confidence < 0 ||
          confidence > 1 ||
          (direction != null &&
              (direction is! num ||
                  !direction.isFinite ||
                  direction < 0 ||
                  direction >= 360)) ||
          (item['primaryAction'] != null && primaryAction == null) ||
          (item['fallbackAction'] != null && fallbackAction == null) ||
          hints is! List ||
          hints.length > 4 ||
          hints.any(
            (hint) =>
                hint is! String ||
                hint.trim().isEmpty ||
                hint.runes.length > 40 ||
                hint.contains(RegExp(r'[\r\n]')),
          ) ||
          evidence == null ||
          !ids.add(id)) {
        return const [];
      }
      opportunities.add(
        PhotographyOpportunity(
          id: id,
          kind: kind,
          title: (item['title'] as String).trim(),
          startsAt: startsAt,
          peaksAt: peaksAt,
          expiresAt: expiresAt,
          score: score,
          confidence: confidence,
          geoScope: scope,
          directionDegrees: (direction as num?)?.toDouble(),
          primaryAction: primaryAction,
          fallbackAction: fallbackAction,
          equipmentHints: hints.cast<String>(),
          evidence: evidence,
        ),
      );
    }
    return List.unmodifiable(opportunities);
  }

  List<PhotographyEvidence>? _decodePhotographyEvidence(Object? raw) {
    if (raw is! List || raw.isEmpty || raw.length > 4) return null;
    final result = <PhotographyEvidence>[];
    for (final value in raw) {
      if (value is! Map) return null;
      final item = Map<String, Object?>.from(value);
      if (!_hasExactKeys(item, const {
            'id',
            'kind',
            'statement',
            'confidence',
            'supports',
          }) ||
          item['id'] is! String ||
          item['id'].toString().isEmpty ||
          item['statement'] is! String ||
          (item['statement'] as String).trim().isEmpty ||
          (item['statement'] as String).runes.length > 120 ||
          _enumByName(PhotographyEvidenceKind.values, item['kind']) == null ||
          _double(item['confidence']) == null ||
          _double(item['confidence'])! < 0 ||
          _double(item['confidence'])! > 1 ||
          item['supports'] is! bool) {
        return null;
      }
      result.add(
        PhotographyEvidence(
          id: item['id'] as String,
          kind: _enumByName(PhotographyEvidenceKind.values, item['kind'])!,
          statement: (item['statement'] as String).trim(),
          confidence: _double(item['confidence'])!,
          supports: item['supports'] as bool,
        ),
      );
    }
    return List.unmodifiable(result);
  }

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
        (action == ContextAction.openAuthority &&
            (source != ContextEventSource.astronomyCatalog ||
                rawTitle is! String ||
                sourceUri == null)) ||
        (action != ContextAction.openAuthority && rawSourceUrl != null)) {
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
    if (latitude == null || longitude == null || system == null) return null;
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

  /// Canonical sentinel returned by [_decodeManifest] when the persisted
  /// manifest data fails validation. Signals the caller to discard the
  /// entire snapshot rather than silently treating a corrupt manifest as
  /// "no manifest".
  ///
  /// Using [Object] identity rather than `null` preserves the semantic
  /// distinction: `null` means "no manifest stored", the sentinel means
  /// "manifest was stored but is unrecoverable".
  static const _manifestDecodeFailure = Object();

  Map<String, Object?> _encodeManifest(ServerManifest manifest) => {
    'layout': manifest.layout.name,
    'primaryEventId': manifest.primaryEventId,
    'secondaryEventIds': manifest.secondaryEventIds,
    'safetyEventIds': manifest.safetyEventIds,
  };

  /// Decodes a [ServerManifest] from raw cache data.
  ///
  /// Returns `null` when the key is absent (`raw` is null or not a [Map]),
  /// meaning "no manifest" — compatible with old cache entries. Returns
  /// [_manifestDecodeFailure] when the data is structurally present but
  /// cannot form a valid manifest (unknown layout, wrong types, or
  /// construction-rule violations). The caller must propagate this sentinel
  /// to abort the snapshot decode.
  Object? _decodeManifest(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return _manifestDecodeFailure;
    final layout = ServerManifestLayout.fromServerString(raw['layout']);
    if (layout == null) return _manifestDecodeFailure;
    final primaryEventId = raw['primaryEventId'];
    if (primaryEventId is! String? && primaryEventId != null) {
      return _manifestDecodeFailure;
    }
    final secondary = _stringList(raw['secondaryEventIds']);
    final safety = _stringList(raw['safetyEventIds']);
    try {
      return ServerManifest(
        layout: layout,
        primaryEventId: primaryEventId as String?,
        secondaryEventIds: secondary,
        safetyEventIds: safety,
      );
    } on ArgumentError {
      return _manifestDecodeFailure;
    }
  }

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
