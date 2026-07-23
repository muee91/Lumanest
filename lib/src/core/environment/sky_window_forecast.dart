import 'package:luma_nest/src/core/location/geo_point.dart';

enum SkyWindowConditionBand {
  favorable,
  conditional,
  unavailable,
  insufficientData,
}

enum SkyWindowConfidenceBand { low, medium, high }

enum MoonInterferenceBand { low, moderate, high }

class SkyWindowGeometry {
  const SkyWindowGeometry({
    required this.astronomicalNight,
    required this.galacticCenterAzimuthDegrees,
    required this.galacticCenterAltitudeDegrees,
    required this.sunAltitudeDegrees,
  });

  final bool astronomicalNight;
  final double galacticCenterAzimuthDegrees;
  final double galacticCenterAltitudeDegrees;
  final double sunAltitudeDegrees;
}

class SkyWindowTerrain {
  const SkyWindowTerrain({
    required this.status,
    required this.horizonAltitudeDegrees,
    required this.clearanceDegrees,
    required this.obstructionDistanceKm,
    required this.coverageRatio,
  });

  final String status;
  final double? horizonAltitudeDegrees;
  final double? clearanceDegrees;
  final double? obstructionDistanceKm;
  final double? coverageRatio;
}

class SkyWindowMoon {
  const SkyWindowMoon({
    required this.azimuthDegrees,
    required this.altitudeDegrees,
    required this.illuminationFraction,
    required this.phaseAngleDegrees,
    required this.angularSeparationFromGalacticCenterDegrees,
    required this.terrainBlocked,
    required this.terrainClearanceDegrees,
    required this.interferenceBand,
    required this.modelVersion,
  });

  final double azimuthDegrees;
  final double altitudeDegrees;
  final double illuminationFraction;
  final double phaseAngleDegrees;
  final double angularSeparationFromGalacticCenterDegrees;
  final bool terrainBlocked;
  final double? terrainClearanceDegrees;
  final MoonInterferenceBand interferenceBand;
  final String modelVersion;
}

class SkyWindowAtmosphere {
  const SkyWindowAtmosphere({
    required this.status,
    required this.conditionBand,
    required this.totalCloudCoverPercent,
    required this.lowCloudCoverPercent,
    required this.middleCloudCoverPercent,
    required this.highCloudCoverPercent,
    required this.visibilityMeters,
    required this.precipitationProbabilityPercent,
    required this.precipitationMm,
    required this.relativeHumidityPercent,
    required this.windSpeedKmh,
    required this.windGustKmh,
  });

  final String status;
  final SkyWindowConditionBand conditionBand;
  final double? totalCloudCoverPercent;
  final double? lowCloudCoverPercent;
  final double? middleCloudCoverPercent;
  final double? highCloudCoverPercent;
  final double? visibilityMeters;
  final double? precipitationProbabilityPercent;
  final double? precipitationMm;
  final double? relativeHumidityPercent;
  final double? windSpeedKmh;
  final double? windGustKmh;
}

class SkyWindowLightPollution {
  const SkyWindowLightPollution({
    required this.status,
    required this.direction,
    required this.p90,
    required this.relativeRadianceBand,
    required this.coverageRatio,
    required this.dominantDirection,
    required this.dominantAngularSeparationDegrees,
  });

  final String status;
  final String? direction;
  final double? p90;
  final String? relativeRadianceBand;
  final double? coverageRatio;
  final String? dominantDirection;
  final double? dominantAngularSeparationDegrees;
}

class SkyWindowAssessment {
  const SkyWindowAssessment({
    required this.observedAt,
    required this.conditionBand,
    required this.geometry,
    required this.terrain,
    required this.moon,
    required this.atmosphere,
    required this.lightPollution,
    required this.weatherAgreement,
    required this.limitations,
  });

  final DateTime observedAt;
  final SkyWindowConditionBand conditionBand;
  final SkyWindowGeometry? geometry;
  final SkyWindowTerrain terrain;
  final SkyWindowMoon? moon;
  final SkyWindowAtmosphere atmosphere;
  final SkyWindowLightPollution lightPollution;
  final String weatherAgreement;
  final List<String> limitations;
}

class SkyWindowCandidate {
  const SkyWindowCandidate({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.peakAt,
    required this.conditionBand,
    required this.sampleCount,
    required this.favorableSamples,
    required this.conditionalSamples,
    required this.peakAssessment,
    required this.primaryReasons,
  });

  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime peakAt;
  final SkyWindowConditionBand conditionBand;
  final int sampleCount;
  final int favorableSamples;
  final int conditionalSamples;
  final SkyWindowAssessment peakAssessment;
  final List<String> primaryReasons;
}

class SkyWindowConfidence {
  const SkyWindowConfidence({
    required this.band,
    required this.criticalSourcesReady,
    required this.missingSources,
    required this.conflicts,
  });

  final SkyWindowConfidenceBand band;
  final bool criticalSourcesReady;
  final List<String> missingSources;
  final List<String> conflicts;
}

class SkyBrightnessCalibration {
  const SkyBrightnessCalibration({
    required this.status,
    required this.sampleCount,
    required this.sqmMedian,
    required this.limitingMagnitudeMedian,
    required this.distanceKm,
    required this.limitation,
  });

  final String status;
  final int sampleCount;
  final double? sqmMedian;
  final double? limitingMagnitudeMedian;
  final double? distanceKm;
  final String? limitation;
}

class SkyWindowForecast {
  const SkyWindowForecast({
    required this.algorithmVersion,
    required this.requestedCoordinate,
    required this.requestedStartAt,
    required this.endAt,
    required this.stepMinutes,
    required this.generatedAt,
    required this.expiresAt,
    required this.current,
    required this.windows,
    required this.bestWindowId,
    required this.confidence,
    required this.calibration,
  });

  final String algorithmVersion;
  final GeoPoint requestedCoordinate;
  final DateTime requestedStartAt;
  final DateTime endAt;
  final int stepMinutes;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final SkyWindowAssessment current;
  final List<SkyWindowCandidate> windows;
  final String? bestWindowId;
  final SkyWindowConfidence confidence;
  final SkyBrightnessCalibration calibration;

  SkyWindowCandidate? get bestWindow {
    final id = bestWindowId;
    if (id == null) return null;
    for (final window in windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  factory SkyWindowForecast.fromJson(Map<String, Object?> json) {
    if (_integer(json['contractVersion'], minimum: 1, maximum: 1) != 1) {
      throw const FormatException('Unsupported sky-window contract');
    }
    final algorithmVersion = _requiredString(json['algorithmVersion'], 80);
    if (algorithmVersion != 'sky-window-forecast.1') {
      throw const FormatException('Unsupported sky-window algorithm');
    }
    final requestedCoordinate = _coordinate(json['requestedCoordinate']);
    final requestedStartAt = _date(json['requestedStartAt']);
    final endAt = _date(json['endAt']);
    final stepMinutes = _integer(json['stepMinutes'], minimum: 15, maximum: 15);
    final generatedAt = _date(json['generatedAt']);
    final expiresAt = _date(json['expiresAt']);
    if (!endAt.isAfter(requestedStartAt) || !expiresAt.isAfter(generatedAt)) {
      throw const FormatException('Invalid sky-window time range');
    }
    final current = _assessment(_map(json['current']));
    if (current.observedAt.difference(requestedStartAt).inMilliseconds.abs() > 1) {
      throw const FormatException('Current sky-window time mismatch');
    }
    final rawWindows = _list(json['windows']);
    if (rawWindows.length > 8) {
      throw const FormatException('Too many sky windows');
    }
    final windows = rawWindows.map((value) => _candidate(_map(value))).toList(growable: false);
    DateTime? previousStart;
    final ids = <String>{};
    for (final window in windows) {
      if (!ids.add(window.id) || !window.endAt.isAfter(window.startAt) ||
          window.startAt.isBefore(requestedStartAt) || window.endAt.isAfter(endAt) ||
          window.peakAt.isBefore(window.startAt) || window.peakAt.isAfter(window.endAt) ||
          (previousStart != null && window.startAt.isBefore(previousStart))) {
        throw const FormatException('Invalid sky-window candidate');
      }
      previousStart = window.startAt;
    }
    final bestWindowId = _optionalString(json['bestWindowId'], 80);
    if (bestWindowId != null && !ids.contains(bestWindowId)) {
      throw const FormatException('Unknown best sky window');
    }
    return SkyWindowForecast(
      algorithmVersion: algorithmVersion,
      requestedCoordinate: requestedCoordinate,
      requestedStartAt: requestedStartAt,
      endAt: endAt,
      stepMinutes: stepMinutes,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      current: current,
      windows: windows,
      bestWindowId: bestWindowId,
      confidence: _confidence(_map(json['confidence'])),
      calibration: _calibration(_map(json['calibration'])),
    );
  }
}

SkyWindowAssessment _assessment(Map<String, Object?> value) {
  final geometryValue = value['geometry'];
  final moonValue = value['moon'];
  final auxiliary = _map(value['auxiliary']);
  return SkyWindowAssessment(
    observedAt: _date(value['observedAt']),
    conditionBand: _condition(value['conditionBand']),
    geometry: geometryValue == null ? null : _geometry(_map(geometryValue)),
    terrain: _terrain(_map(value['terrain'])),
    moon: moonValue == null ? null : _moon(_map(moonValue)),
    atmosphere: _atmosphere(_map(value['atmosphere'])),
    lightPollution: _light(_map(value['lightPollution'])),
    weatherAgreement: _requiredString(auxiliary['weatherAgreement'], 32),
    limitations: _strings(value['limitations'], maximumItems: 32),
  );
}

SkyWindowCandidate _candidate(Map<String, Object?> value) {
  final condition = _condition(value['conditionBand']);
  if (condition != SkyWindowConditionBand.favorable &&
      condition != SkyWindowConditionBand.conditional) {
    throw const FormatException('Window is not usable');
  }
  return SkyWindowCandidate(
    id: _requiredString(value['id'], 80),
    startAt: _date(value['startAt']),
    endAt: _date(value['endAt']),
    peakAt: _date(value['peakAt']),
    conditionBand: condition,
    sampleCount: _integer(value['sampleCount'], minimum: 2, maximum: 400),
    favorableSamples: _integer(value['favorableSamples'], minimum: 0, maximum: 400),
    conditionalSamples: _integer(value['conditionalSamples'], minimum: 0, maximum: 400),
    peakAssessment: _assessment(_map(value['peakAssessment'])),
    primaryReasons: _strings(value['primaryReasons'], maximumItems: 4),
  );
}

SkyWindowGeometry _geometry(Map<String, Object?> value) {
  final sun = _map(value['sun']);
  final galaxy = _map(value['galacticCenter']);
  return SkyWindowGeometry(
    astronomicalNight: _boolean(value['astronomicalNight']),
    galacticCenterAzimuthDegrees: _number(galaxy['azimuthDegrees'], 0, 360),
    galacticCenterAltitudeDegrees: _number(galaxy['altitudeDegrees'], -90, 90),
    sunAltitudeDegrees: _number(sun['altitudeDegrees'], -90, 90),
  );
}

SkyWindowTerrain _terrain(Map<String, Object?> value) => SkyWindowTerrain(
  status: _requiredString(value['status'], 32),
  horizonAltitudeDegrees: _nullableNumber(value['horizonAltitudeDegrees'], -90, 90),
  clearanceDegrees: _nullableNumber(value['clearanceDegrees'], -180, 180),
  obstructionDistanceKm: _nullableNumber(value['obstructionDistanceKm'], 0, 40),
  coverageRatio: _nullableNumber(value['coverageRatio'], 0, 1),
);

SkyWindowMoon _moon(Map<String, Object?> value) => SkyWindowMoon(
  azimuthDegrees: _number(value['azimuthDegrees'], 0, 360),
  altitudeDegrees: _number(value['altitudeDegrees'], -90, 90),
  illuminationFraction: _number(value['illuminationFraction'], 0, 1),
  phaseAngleDegrees: _number(value['phaseAngleDegrees'], 0, 180),
  angularSeparationFromGalacticCenterDegrees:
      _number(value['angularSeparationFromGalacticCenterDegrees'], 0, 180),
  terrainBlocked: _boolean(value['terrainBlocked']),
  terrainClearanceDegrees: _nullableNumber(value['terrainClearanceDegrees'], -180, 180),
  interferenceBand: MoonInterferenceBand.values.byName(
    _requiredString(value['interferenceBand'], 16),
  ),
  modelVersion: _requiredString(value['modelVersion'], 80),
);

SkyWindowAtmosphere _atmosphere(Map<String, Object?> value) => SkyWindowAtmosphere(
  status: _requiredString(value['status'], 32),
  conditionBand: _condition(value['conditionBand']),
  totalCloudCoverPercent: _nullableNumber(value['totalCloudCoverPercent'], 0, 100),
  lowCloudCoverPercent: _nullableNumber(value['lowCloudCoverPercent'], 0, 100),
  middleCloudCoverPercent: _nullableNumber(value['middleCloudCoverPercent'], 0, 100),
  highCloudCoverPercent: _nullableNumber(value['highCloudCoverPercent'], 0, 100),
  visibilityMeters: _nullableNumber(value['visibilityMeters'], 0, 100000),
  precipitationProbabilityPercent:
      _nullableNumber(value['precipitationProbabilityPercent'], 0, 100),
  precipitationMm: _nullableNumber(value['precipitationMm'], 0, 500),
  relativeHumidityPercent: _nullableNumber(value['relativeHumidityPercent'], 0, 100),
  windSpeedKmh: _nullableNumber(value['windSpeedKmh'], 0, 400),
  windGustKmh: _nullableNumber(value['windGustKmh'], 0, 500),
);

SkyWindowLightPollution _light(Map<String, Object?> value) => SkyWindowLightPollution(
  status: _requiredString(value['status'], 32),
  direction: _optionalString(value['direction'], 32),
  p90: _nullableNumber(value['p90'], 0, 1000000),
  relativeRadianceBand: _optionalString(value['relativeRadianceBand'], 32),
  coverageRatio: _nullableNumber(value['coverageRatio'], 0, 1),
  dominantDirection: _optionalString(value['dominantDirection'], 32),
  dominantAngularSeparationDegrees:
      _nullableNumber(value['dominantAngularSeparationDegrees'], 0, 180),
);

SkyWindowConfidence _confidence(Map<String, Object?> value) => SkyWindowConfidence(
  band: SkyWindowConfidenceBand.values.byName(_requiredString(value['band'], 16)),
  criticalSourcesReady: _boolean(value['criticalSourcesReady']),
  missingSources: _strings(value['missingSources'], maximumItems: 16),
  conflicts: _strings(value['conflicts'], maximumItems: 16),
);

SkyBrightnessCalibration _calibration(Map<String, Object?> value) => SkyBrightnessCalibration(
  status: _requiredString(value['status'], 32),
  sampleCount: _integer(value['sampleCount'], minimum: 0, maximum: 10000000),
  sqmMedian: _nullableNumber(value['sqmMedian'], 10, 30),
  limitingMagnitudeMedian: _nullableNumber(value['limitingMagnitudeMedian'], -2, 9),
  distanceKm: _nullableNumber(value['distanceKm'], 0, 50),
  limitation: _optionalString(value['limitation'], 120),
);

SkyWindowConditionBand _condition(Object? value) =>
    SkyWindowConditionBand.values.byName(_requiredString(value, 32));

GeoPoint _coordinate(Object? value) {
  final map = _map(value);
  if (map['system'] != 'wgs84') throw const FormatException('Expected WGS84 coordinate');
  return GeoPoint(
    latitude: _number(map['latitude'], -90, 90),
    longitude: _number(map['longitude'], -180, 180),
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected list');
  return value;
}

List<String> _strings(Object? value, {required int maximumItems}) {
  final list = _list(value);
  if (list.length > maximumItems) throw const FormatException('Too many strings');
  return list.map((item) => _requiredString(item, 120)).toList(growable: false);
}

String _requiredString(Object? value, int maximum) {
  if (value is! String || value.isEmpty || value.length > maximum) {
    throw const FormatException('Expected bounded string');
  }
  return value;
}

String? _optionalString(Object? value, int maximum) =>
    value == null ? null : _requiredString(value, maximum);

double _number(Object? value, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum) {
    throw const FormatException('Expected bounded number');
  }
  return value.toDouble();
}

double? _nullableNumber(Object? value, double minimum, double maximum) =>
    value == null ? null : _number(value, minimum, maximum);

int _integer(Object? value, {required int minimum, required int maximum}) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Expected bounded integer');
  }
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

DateTime _date(Object? value) {
  final text = _requiredString(value, 40);
  final date = DateTime.tryParse(text)?.toUtc();
  if (date == null || !text.endsWith('Z')) throw const FormatException('Expected UTC date');
  return date;
}
