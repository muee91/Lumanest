import 'package:luma_nest/src/core/location/geo_point.dart';

enum SiteFactStatus { ready, unconfigured, unavailable }

enum RelativeRadianceBand { veryDark, dark, moderate, bright, veryBright }

class TerrainFact {
  const TerrainFact({
    required this.status,
    required this.elevationMeters,
    required this.sourceId,
    required this.resolutionMeters,
    required this.attribution,
  });

  final SiteFactStatus status;
  final double? elevationMeters;
  final String? sourceId;
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
    required this.resolutionMeters,
    required this.sourceId,
    required this.attribution,
  });

  final SiteFactStatus status;
  final double? radiance;
  final RelativeRadianceBand? relativeRadianceBand;
  final String classificationVersion;
  final int? datasetYear;
  final double? resolutionMeters;
  final String? sourceId;
  final String? attribution;

  bool get isUsable => status == SiteFactStatus.ready && radiance != null;
}

class SiteEnvironmentFacts {
  const SiteEnvironmentFacts({
    required this.coordinate,
    required this.terrain,
    required this.nightSkyBackground,
    required this.generatedAt,
    required this.expiresAt,
    required this.cacheStatus,
  });

  final GeoPoint coordinate;
  final TerrainFact terrain;
  final NightSkyBackgroundFact nightSkyBackground;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final String cacheStatus;

  static SiteEnvironmentFacts fromJson(Map<String, Object?> body) {
    const rootKeys = {
      'contractVersion',
      'coordinate',
      'terrain',
      'nightSkyBackground',
      'generatedAt',
      'expiresAt',
      'cacheStatus',
    };
    if (!_exactKeys(body, rootKeys) || body['contractVersion'] != 1) {
      throw const FormatException('Invalid site environment contract');
    }
    final coordinate = _map(body['coordinate']);
    final terrain = _map(body['terrain']);
    final nightSky = _map(body['nightSkyBackground']);
    final generatedAt = DateTime.tryParse('${body['generatedAt'] ?? ''}');
    final expiresAt = DateTime.tryParse('${body['expiresAt'] ?? ''}');
    if (!_exactKeys(coordinate, const {'latitude', 'longitude', 'system'}) ||
        coordinate['system'] != 'wgs84' ||
        !_finiteIn(coordinate['latitude'], -90, 90) ||
        !_finiteIn(coordinate['longitude'], -180, 180) ||
        generatedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(generatedAt) ||
        body['cacheStatus'] is! String) {
      throw const FormatException('Invalid site environment metadata');
    }
    return SiteEnvironmentFacts(
      coordinate: GeoPoint(
        latitude: (coordinate['latitude']! as num).toDouble(),
        longitude: (coordinate['longitude']! as num).toDouble(),
      ),
      terrain: _terrain(terrain),
      nightSkyBackground: _nightSky(nightSky),
      generatedAt: generatedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      cacheStatus: body['cacheStatus']! as String,
    );
  }

  static TerrainFact _terrain(Map<String, Object?> value) {
    if (!_exactKeys(value, const {'status', 'elevationMeters', 'source'})) {
      throw const FormatException('Invalid terrain fact');
    }
    final status = _status(value['status']);
    final elevation = value['elevationMeters'];
    if (status == SiteFactStatus.ready && !_finiteIn(elevation, -500, 9000)) {
      throw const FormatException('Invalid terrain elevation');
    }
    final source = value['source'] == null ? null : _map(value['source']);
    if (status == SiteFactStatus.ready &&
        (source == null ||
            !_exactKeys(
              source,
              const {'id', 'dataset', 'resolutionMeters', 'attribution'},
            ) ||
            source['id'] is! String ||
            source['attribution'] is! String ||
            !_finiteIn(source['resolutionMeters'], 1, 10000))) {
      throw const FormatException('Invalid terrain source');
    }
    return TerrainFact(
      status: status,
      elevationMeters: elevation is num ? elevation.toDouble() : null,
      sourceId: source?['id'] as String?,
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
      'resolutionMeters',
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
    final resolution = value['resolutionMeters'];
    final source = value['source'] == null ? null : _map(value['source']);
    if (status == SiteFactStatus.ready &&
        (!_finiteIn(radiance, 0, 1000000) ||
            band == null ||
            datasetYear is! int ||
            datasetYear < 2012 ||
            datasetYear > 2100 ||
            !_finiteIn(resolution, 1, 10000) ||
            source == null ||
            !_exactKeys(source, const {'id', 'attribution'}) ||
            source['id'] is! String ||
            source['attribution'] is! String)) {
      throw const FormatException('Invalid ready night-sky fact');
    }
    return NightSkyBackgroundFact(
      status: status,
      radiance: radiance is num ? radiance.toDouble() : null,
      relativeRadianceBand: band,
      classificationVersion: value['classificationVersion']! as String,
      datasetYear: datasetYear as int?,
      resolutionMeters: (resolution as num?)?.toDouble(),
      sourceId: source?['id'] as String?,
      attribution: source?['attribution'] as String?,
    );
  }

  static SiteFactStatus _status(Object? value) => SiteFactStatus.values
      .where((item) => item.name == value)
      .firstOrNull ??
      (throw const FormatException('Invalid site fact status'));

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected object');
    return Map<String, Object?>.from(value);
  }

  static bool _exactKeys(Map<Object?, Object?> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  static bool _finiteIn(Object? value, double minimum, double maximum) =>
      value is num && value.isFinite && value >= minimum && value <= maximum;
}
