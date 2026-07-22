import 'package:luma_nest/src/core/location/geo_point.dart';

enum SiteFactStatus { ready, unconfigured, unavailable }

enum RelativeRadianceBand { veryDark, dark, moderate, bright, veryBright }

class TerrainFact {
  const TerrainFact({
    required this.status,
    required this.elevationMeters,
    required this.sampledCoordinate,
    required this.generatedAt,
    required this.expiresAt,
    required this.cacheStatus,
    required this.sourceId,
    required this.sourceRevision,
    required this.resolutionMeters,
    required this.attribution,
  });

  final SiteFactStatus status;
  final double? elevationMeters;
  final GeoPoint sampledCoordinate;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final String cacheStatus;
  final String? sourceId;
  final String? sourceRevision;
  final double? resolutionMeters;
  final String? attribution;
}

class NightSkyBackgroundFact {
  const NightSkyBackgroundFact({
    required this.status,
    required this.radiance,
    required this.relativeRadianceBand,
    required this.classificationVersion,
    required this.datasetYear,
    required this.datasetRevision,
    required this.resolutionMeters,
    required this.sampledCoordinate,
    required this.generatedAt,
    required this.expiresAt,
    required this.cacheStatus,
    required this.sourceId,
    required this.attribution,
  });

  final SiteFactStatus status;
  final double? radiance;
  final RelativeRadianceBand? relativeRadianceBand;
  final String classificationVersion;
  final int? datasetYear;
  final String? datasetRevision;
  final double? resolutionMeters;
  final GeoPoint sampledCoordinate;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final String cacheStatus;
  final String? sourceId;
  final String? attribution;

  bool get isUsable => status == SiteFactStatus.ready && radiance != null;
}

class SiteEnvironmentFacts {
  const SiteEnvironmentFacts({
    required this.requestedCoordinate,
    required this.terrain,
    required this.nightSkyBackground,
    required this.generatedAt,
  });

  final GeoPoint requestedCoordinate;
  final TerrainFact terrain;
  final NightSkyBackgroundFact nightSkyBackground;
  final DateTime generatedAt;

  GeoPoint get coordinate => requestedCoordinate;

  DateTime get expiresAt => terrain.expiresAt.isBefore(nightSkyBackground.expiresAt)
      ? terrain.expiresAt
      : nightSkyBackground.expiresAt;

  String get cacheStatus => terrain.cacheStatus == nightSkyBackground.cacheStatus
      ? terrain.cacheStatus
      : 'mixed';

  static SiteEnvironmentFacts fromJson(Map<String, Object?> body) {
    const rootKeys = {
      'contractVersion',
      'requestedCoordinate',
      'terrain',
      'nightSkyBackground',
      'generatedAt',
    };
    if (!_exactKeys(body, rootKeys) || body['contractVersion'] != 2) {
      throw const FormatException('Invalid site environment contract');
    }
    final generatedAt = _date(body['generatedAt']);
    return SiteEnvironmentFacts(
      requestedCoordinate: _coordinate(body['requestedCoordinate']),
      terrain: _terrain(_map(body['terrain'])),
      nightSkyBackground: _nightSky(_map(body['nightSkyBackground'])),
      generatedAt: generatedAt,
    );
  }

  static TerrainFact _terrain(Map<String, Object?> value) {
    const keys = {
      'status',
      'elevationMeters',
      'sampledCoordinate',
      'generatedAt',
      'expiresAt',
      'cacheStatus',
      'source',
    };
    if (!_exactKeys(value, keys)) {
      throw const FormatException('Invalid terrain fact');
    }
    final status = _status(value['status']);
    final elevation = value['elevationMeters'];
    final generatedAt = _date(value['generatedAt']);
    final expiresAt = _date(value['expiresAt']);
    final cacheStatus = _cacheStatus(value['cacheStatus']);
    if (!expiresAt.isAfter(generatedAt)) {
      throw const FormatException('Invalid terrain freshness');
    }
    if (status == SiteFactStatus.ready && !_finiteIn(elevation, -500, 9000)) {
      throw const FormatException('Invalid terrain elevation');
    }
    final source = value['source'] == null ? null : _map(value['source']);
    if (status == SiteFactStatus.ready &&
        (source == null ||
            !_exactKeys(
              source,
              const {
                'id',
                'dataset',
                'revision',
                'resolutionMeters',
                'attribution',
              },
            ) ||
            source['id'] is! String ||
            source['revision'] is! String ||
            source['attribution'] is! String ||
            !_finiteIn(source['resolutionMeters'], 1, 10000))) {
      throw const FormatException('Invalid terrain source');
    }
    return TerrainFact(
      status: status,
      elevationMeters: elevation is num ? elevation.toDouble() : null,
      sampledCoordinate: _coordinate(value['sampledCoordinate']),
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      cacheStatus: cacheStatus,
      sourceId: source?['id'] as String?,
      sourceRevision: source?['revision'] as String?,
      resolutionMeters: (source?['resolutionMeters'] as num?)?.toDouble(),
      attribution: source?['attribution'] as String?,
    );
  }

  static NightSkyBackgroundFact _nightSky(Map<String, Object?> value) {
    const keys = {
      'status',
      'radiance',
      'radianceUnit',
      'relativeRadianceBand',
      'classificationVersion',
      'datasetYear',
      'datasetRevision',
      'resolutionMeters',
      'sampledCoordinate',
      'generatedAt',
      'expiresAt',
      'cacheStatus',
      'source',
    };
    if (!_exactKeys(value, keys) ||
        value['radianceUnit'] != 'nW/cm2/sr' ||
        value['classificationVersion'] != 'viirs-relative-radiance.1') {
      throw const FormatException('Invalid night-sky background fact');
    }
    final status = _status(value['status']);
    final radiance = value['radiance'];
    final band = RelativeRadianceBand.values
        .where((item) => item.name == value['relativeRadianceBand'])
        .firstOrNull;
    final datasetYear = value['datasetYear'];
    final datasetRevision = value['datasetRevision'];
    final resolution = value['resolutionMeters'];
    final generatedAt = _date(value['generatedAt']);
    final expiresAt = _date(value['expiresAt']);
    final cacheStatus = _cacheStatus(value['cacheStatus']);
    if (!expiresAt.isAfter(generatedAt)) {
      throw const FormatException('Invalid night-sky freshness');
    }
    final source = value['source'] == null ? null : _map(value['source']);
    if (status == SiteFactStatus.ready &&
        (!_finiteIn(radiance, 0, 1000000) ||
            band == null ||
            datasetYear is! int ||
            datasetYear < 2012 ||
            datasetYear > 2100 ||
            datasetRevision is! String ||
            datasetRevision.isEmpty ||
            !_finiteIn(resolution, 1, 10000) ||
            source == null ||
            !_exactKeys(source, const {'id', 'revision', 'attribution'}) ||
            source['id'] is! String ||
            source['revision'] != datasetRevision ||
            source['attribution'] is! String)) {
      throw const FormatException('Invalid ready night-sky fact');
    }
    return NightSkyBackgroundFact(
      status: status,
      radiance: radiance is num ? radiance.toDouble() : null,
      relativeRadianceBand: band,
      classificationVersion: value['classificationVersion']! as String,
      datasetYear: datasetYear as int?,
      datasetRevision: datasetRevision as String?,
      resolutionMeters: (resolution as num?)?.toDouble(),
      sampledCoordinate: _coordinate(value['sampledCoordinate']),
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      cacheStatus: cacheStatus,
      sourceId: source?['id'] as String?,
      attribution: source?['attribution'] as String?,
    );
  }

  static SiteFactStatus _status(Object? value) => SiteFactStatus.values
      .where((item) => item.name == value)
      .firstOrNull ??
      (throw const FormatException('Invalid site fact status'));

  static String _cacheStatus(Object? value) {
    if (value is String && const {'hit', 'miss', 'coalesced'}.contains(value)) {
      return value;
    }
    throw const FormatException('Invalid site fact cache status');
  }

  static GeoPoint _coordinate(Object? value) {
    final coordinate = _map(value);
    if (!_exactKeys(coordinate, const {'latitude', 'longitude', 'system'}) ||
        coordinate['system'] != 'wgs84' ||
        !_finiteIn(coordinate['latitude'], -90, 90) ||
        !_finiteIn(coordinate['longitude'], -180, 180)) {
      throw const FormatException('Invalid site fact coordinate');
    }
    return GeoPoint(
      latitude: (coordinate['latitude']! as num).toDouble(),
      longitude: (coordinate['longitude']! as num).toDouble(),
    );
  }

  static DateTime _date(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) throw const FormatException('Invalid site fact timestamp');
    return parsed.toUtc();
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected object');
    return Map<String, Object?>.from(value);
  }

  static bool _exactKeys(Map<Object?, Object?> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  static bool _finiteIn(Object? value, double minimum, double maximum) =>
      value is num && value.isFinite && value >= minimum && value <= maximum;
}
