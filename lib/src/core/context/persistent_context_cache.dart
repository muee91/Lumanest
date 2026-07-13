import 'dart:convert';

import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistentContextCache implements ContextCache {
  PersistentContextCache(
    this._preferences, {
    this.storageKey = 'environment_context_snapshot_v1',
  });

  static const _version = 1;
  final SharedPreferencesAsync _preferences;
  final String storageKey;

  @override
  Future<ContextSnapshot?> readLatest() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw);
      if (body is! Map || body['version'] != _version) return null;
      return _decodeSnapshot(body['snapshot']);
    } on Object {
      // Cached context is optional recovery data. Corruption, a partial write
      // or an incompatible schema must never prevent the live app starting.
      return null;
    }
  }

  @override
  Future<void> write(ContextSnapshot snapshot) {
    return _preferences.setString(
      storageKey,
      jsonEncode({'version': _version, 'snapshot': _encodeSnapshot(snapshot)}),
    );
  }

  @override
  Future<void> clear() => _preferences.remove(storageKey);

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
    'solarElevationDegrees': value.solarElevationDegrees,
    'solarAzimuthDegrees': value.solarAzimuthDegrees,
    'sunrise': value.sunrise?.toUtc().toIso8601String(),
    'sunset': value.sunset?.toUtc().toIso8601String(),
    'isStale': value.isStale,
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
    if (id is! String ||
        observedAt == null ||
        expiresAt == null ||
        scene == null ||
        phase == null ||
        weather == null ||
        activeRoute is! bool) {
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
      dayPhase: phase,
      weather: weather,
      activeRoute: activeRoute,
      opportunityIds: _stringList(raw['opportunityIds']),
      safetyEventIds: _stringList(raw['safetyEventIds']),
      wildlifeEventIds: _stringList(raw['wildlifeEventIds']),
      events: events.toList(growable: false),
      wildlifeActivity: _decodeWildlife(raw['wildlifeActivity']),
      location: _decodePoint(raw['location']),
      temperatureCelsius: _double(raw['temperatureCelsius']),
      windSpeedMetersPerSecond: _double(raw['windSpeedMetersPerSecond']),
      windDirectionDegrees: _double(raw['windDirectionDegrees']),
      visibilityKilometers: _double(raw['visibilityKilometers']),
      precipitationMillimeters: _double(raw['precipitationMillimeters']),
      cloudCoverPercent: _double(raw['cloudCoverPercent']),
      solarElevationDegrees: _double(raw['solarElevationDegrees']),
      solarAzimuthDegrees: _double(raw['solarAzimuthDegrees']),
      sunrise: _date(raw['sunrise']),
      sunset: _date(raw['sunset']),
      isStale: raw['isStale'] == true,
    );
  }

  Map<String, Object?> _encodeEvent(ContextEvent event) => {
    'id': event.id,
    'channel': event.channel.name,
    'source': event.source.name,
    'observedAt': event.observedAt.toUtc().toIso8601String(),
    'expiresAt': event.expiresAt.toUtc().toIso8601String(),
    'confidence': event.confidence,
  };

  ContextEvent? _decodeEvent(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final channel = _enumByName(ContextEventChannel.values, raw['channel']);
    final source = _enumByName(ContextEventSource.values, raw['source']);
    final observedAt = _date(raw['observedAt']);
    final expiresAt = _date(raw['expiresAt']);
    final confidence = _double(raw['confidence']);
    if (id is! String ||
        channel == null ||
        source == null ||
        observedAt == null ||
        expiresAt == null ||
        confidence == null ||
        confidence < 0 ||
        confidence > 1) {
      return null;
    }
    return ContextEvent(
      id: id,
      channel: channel,
      source: source,
      observedAt: observedAt,
      expiresAt: expiresAt,
      confidence: confidence,
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
    'radiusKilometers': activity.radiusKilometers,
    'occurrenceSampleSize': activity.occurrenceSampleSize,
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
      radiusKilometers: radius,
      occurrenceSampleSize: sampleSize,
      taxa: taxa.toList(growable: false),
    );
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static List<String> _stringList(Object? value) =>
      _list(value).whereType<String>().toList(growable: false);

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
