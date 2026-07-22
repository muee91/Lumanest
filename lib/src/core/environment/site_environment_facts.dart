import 'package:luma_nest/src/core/location/geo_point.dart';

enum SiteFactStatus { ready, unconfigured, unavailable }

enum RelativeRadianceBand { veryDark, dark, moderate, bright, veryBright }

enum LightDomeDirection {
  north,
  northeast,
  east,
  southeast,
  south,
  southwest,
  west,
  northwest,
}

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

class RadianceNeighborhood {
  const RadianceNeighborhood({
    required this.radiusKm,
    required this.sampleCount,
    required this.coverageRatio,
    required this.median,
    required this.p90,
    required this.maximum,
    required this.relativeRadianceBand,
  });

  final double radiusKm;
  final int sampleCount;
  final double coverageRatio;
  final double? median;
  final double? p90;
  final double? maximum;
  final RelativeRadianceBand? relativeRadianceBand;

  bool get hasSamples => sampleCount > 0;
}

class LightDomeSector {
  const LightDomeSector({
    required this.direction,
    required this.azimuthCenterDegrees,
    required this.sampleCount,
    required this.coverageRatio,
    required this.median,
    required this.p90,
    required this.maximum,
    required this.peakDistanceKm,
    required this.relativeRadianceBand,
  });

  final LightDomeDirection direction;
  final double azimuthCenterDegrees;
  final int sampleCount;
  final double coverageRatio;
  final double? median;
  final double? p90;
  final double? maximum;
  final double? peakDistanceKm;
  final RelativeRadianceBand? relativeRadianceBand;

  bool get hasSamples => sampleCount > 0;
}

class LightDomeAnalysis {
  const LightDomeAnalysis({
    required this.innerRadiusKm,
    required this.outerRadiusKm,
    required this.sectorCount,
    required this.dominantDirection,
    required this.dominantAzimuthDegrees,
    required this.sectors,
  });

  final double innerRadiusKm;
  final double outerRadiusKm;
  final int sectorCount;
  final LightDomeDirection? dominantDirection;
  final double? dominantAzimuthDegrees;
  final List<LightDomeSector> sectors;

  LightDomeSector? get dominantSector {
    final direction = dominantDirection;
    if (direction == null) return null;
    return sectors.where((sector) => sector.direction == direction).firstOrNull;
  }
}

class NightSkySpatialAnalysis {
  const NightSkySpatialAnalysis({
    required this.analysisVersion,
    required this.maximumRadiusKm,
    required this.neighborhoods,
    required this.lightDomes,
  });

  final String analysisVersion;
  final double maximumRadiusKm;
  final List<RadianceNeighborhood> neighborhoods;
  final LightDomeAnalysis lightDomes;

  RadianceNeighborhood? neighborhood(double radiusKm) => neighborhoods
      .where((item) => (item.radiusKm - radiusKm).abs() < 0.0001)
      .firstOrNull;
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
    this.spatialAnalysis,
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
  final NightSkySpatialAnalysis? spatialAnalysis;

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
    final contractVersion = body['contractVersion'];
    if (!_exactKeys(body, rootKeys) ||
        (contractVersion != 2 && contractVersion != 3)) {
      throw const FormatException('Invalid site environment contract');
    }
    final generatedAt = _date(body['generatedAt']);
    return SiteEnvironmentFacts(
      requestedCoordinate: _coordinate(body['requestedCoordinate']),
      terrain: _terrain(_map(body['terrain'])),
      nightSkyBackground: _nightSky(
        _map(body['nightSkyBackground']),
        requireSpatialAnalysis: contractVersion == 3,
      ),
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

  static NightSkyBackgroundFact _nightSky(
    Map<String, Object?> value, {
    required bool requireSpatialAnalysis,
  }) {
    final keys = <String>{
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
      if (requireSpatialAnalysis) 'spatialAnalysis',
    };
    if (!_exactKeys(value, keys) ||
        value['radianceUnit'] != 'nW/cm2/sr' ||
        value['classificationVersion'] != 'viirs-relative-radiance.1') {
      throw const FormatException('Invalid night-sky background fact');
    }
    final status = _status(value['status']);
    final radiance = value['radiance'];
    final band = _optionalBand(value['relativeRadianceBand']);
    final datasetYear = value['datasetYear'];
    final datasetRevision = value['datasetRevision'];
    final resolution = value['resolutionMeters'];
    final generatedAt = _date(value['generatedAt']);
    final expiresAt = _date(value['expiresAt']);
    final cacheStatus = _cacheStatus(value['cacheStatus']);
    final spatialAnalysis = requireSpatialAnalysis && value['spatialAnalysis'] != null
        ? _spatialAnalysis(_map(value['spatialAnalysis']))
        : null;
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
            (requireSpatialAnalysis && spatialAnalysis == null) ||
            source == null ||
            !_exactKeys(source, const {'id', 'revision', 'attribution'}) ||
            source['id'] is! String ||
            source['revision'] != datasetRevision ||
            source['attribution'] is! String)) {
      throw const FormatException('Invalid ready night-sky fact');
    }
    if (status != SiteFactStatus.ready && spatialAnalysis != null) {
      throw const FormatException('Unavailable night-sky fact has analysis');
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
      spatialAnalysis: spatialAnalysis,
    );
  }

  static NightSkySpatialAnalysis _spatialAnalysis(Map<String, Object?> value) {
    const keys = {
      'analysisVersion',
      'maximumRadiusKm',
      'neighborhoods',
      'lightDomes',
    };
    if (!_exactKeys(value, keys) ||
        value['analysisVersion'] != 'viirs-spatial-radiance.1' ||
        !_finiteEquals(value['maximumRadiusKm'], 20)) {
      throw const FormatException('Invalid night-sky spatial analysis');
    }
    final rawNeighborhoods = value['neighborhoods'];
    if (rawNeighborhoods is! List || rawNeighborhoods.length != 3) {
      throw const FormatException('Invalid radiance neighborhoods');
    }
    const expectedRadii = [1.0, 5.0, 20.0];
    final neighborhoods = <RadianceNeighborhood>[];
    for (var index = 0; index < expectedRadii.length; index += 1) {
      neighborhoods.add(
        _neighborhood(
          _map(rawNeighborhoods[index]),
          expectedRadiusKm: expectedRadii[index],
        ),
      );
    }
    return NightSkySpatialAnalysis(
      analysisVersion: value['analysisVersion']! as String,
      maximumRadiusKm: (value['maximumRadiusKm']! as num).toDouble(),
      neighborhoods: List.unmodifiable(neighborhoods),
      lightDomes: _lightDomes(_map(value['lightDomes'])),
    );
  }

  static RadianceNeighborhood _neighborhood(
    Map<String, Object?> value, {
    required double expectedRadiusKm,
  }) {
    const keys = {
      'radiusKm',
      'sampleCount',
      'coverageRatio',
      'median',
      'p90',
      'maximum',
      'relativeRadianceBand',
    };
    if (!_exactKeys(value, keys) ||
        !_finiteEquals(value['radiusKm'], expectedRadiusKm)) {
      throw const FormatException('Invalid radiance neighborhood');
    }
    final summary = _summary(value);
    return RadianceNeighborhood(
      radiusKm: expectedRadiusKm,
      sampleCount: summary.sampleCount,
      coverageRatio: summary.coverageRatio,
      median: summary.median,
      p90: summary.p90,
      maximum: summary.maximum,
      relativeRadianceBand: summary.band,
    );
  }

  static LightDomeAnalysis _lightDomes(Map<String, Object?> value) {
    const keys = {
      'innerRadiusKm',
      'outerRadiusKm',
      'sectorCount',
      'dominantDirection',
      'dominantAzimuthDegrees',
      'sectors',
    };
    if (!_exactKeys(value, keys) ||
        !_finiteEquals(value['innerRadiusKm'], 1) ||
        !_finiteEquals(value['outerRadiusKm'], 20) ||
        value['sectorCount'] != 8) {
      throw const FormatException('Invalid light-dome analysis');
    }
    final rawSectors = value['sectors'];
    if (rawSectors is! List || rawSectors.length != 8) {
      throw const FormatException('Invalid light-dome sectors');
    }
    final expectedDirections = LightDomeDirection.values;
    const expectedAzimuths = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0];
    final sectors = <LightDomeSector>[];
    for (var index = 0; index < expectedDirections.length; index += 1) {
      sectors.add(
        _sector(
          _map(rawSectors[index]),
          expectedDirection: expectedDirections[index],
          expectedAzimuthDegrees: expectedAzimuths[index],
        ),
      );
    }
    LightDomeSector? strongest;
    for (final sector in sectors.where((item) => item.hasSamples)) {
      if (strongest == null || _strongerSector(sector, strongest)) {
        strongest = sector;
      }
    }
    final dominantDirection = _optionalDirection(value['dominantDirection']);
    final dominantAzimuth = value['dominantAzimuthDegrees'];
    if (strongest == null) {
      if (dominantDirection != null || dominantAzimuth != null) {
        throw const FormatException('Invalid empty light-dome dominance');
      }
    } else if (dominantDirection != strongest.direction ||
        !_finiteEquals(dominantAzimuth, strongest.azimuthCenterDegrees)) {
      throw const FormatException('Invalid light-dome dominance');
    }
    return LightDomeAnalysis(
      innerRadiusKm: 1,
      outerRadiusKm: 20,
      sectorCount: 8,
      dominantDirection: dominantDirection,
      dominantAzimuthDegrees: dominantAzimuth is num
          ? dominantAzimuth.toDouble()
          : null,
      sectors: List.unmodifiable(sectors),
    );
  }

  static LightDomeSector _sector(
    Map<String, Object?> value, {
    required LightDomeDirection expectedDirection,
    required double expectedAzimuthDegrees,
  }) {
    const keys = {
      'direction',
      'azimuthCenterDegrees',
      'sampleCount',
      'coverageRatio',
      'median',
      'p90',
      'maximum',
      'peakDistanceKm',
      'relativeRadianceBand',
    };
    if (!_exactKeys(value, keys) ||
        _direction(value['direction']) != expectedDirection ||
        !_finiteEquals(value['azimuthCenterDegrees'], expectedAzimuthDegrees)) {
      throw const FormatException('Invalid light-dome sector');
    }
    final summary = _summary(value);
    final peakDistance = value['peakDistanceKm'];
    if ((summary.sampleCount == 0 && peakDistance != null) ||
        (summary.sampleCount > 0 && !_finiteIn(peakDistance, 1, 20))) {
      throw const FormatException('Invalid light-dome peak distance');
    }
    return LightDomeSector(
      direction: expectedDirection,
      azimuthCenterDegrees: expectedAzimuthDegrees,
      sampleCount: summary.sampleCount,
      coverageRatio: summary.coverageRatio,
      median: summary.median,
      p90: summary.p90,
      maximum: summary.maximum,
      peakDistanceKm: peakDistance is num ? peakDistance.toDouble() : null,
      relativeRadianceBand: summary.band,
    );
  }

  static _RadianceSummary _summary(Map<String, Object?> value) {
    final sampleCount = value['sampleCount'];
    final coverageRatio = value['coverageRatio'];
    if (sampleCount is! int ||
        sampleCount < 0 ||
        sampleCount > 10000000 ||
        !_finiteIn(coverageRatio, 0, 1)) {
      throw const FormatException('Invalid radiance sample metadata');
    }
    final median = _optionalRadiance(value['median']);
    final p90 = _optionalRadiance(value['p90']);
    final maximum = _optionalRadiance(value['maximum']);
    final band = _optionalBand(value['relativeRadianceBand']);
    if (sampleCount == 0) {
      if (median != null || p90 != null || maximum != null || band != null) {
        throw const FormatException('Invalid empty radiance summary');
      }
    } else if (median == null ||
        p90 == null ||
        maximum == null ||
        band == null ||
        median > p90 ||
        p90 > maximum ||
        band != _bandFor(p90)) {
      throw const FormatException('Invalid radiance summary');
    }
    return _RadianceSummary(
      sampleCount: sampleCount,
      coverageRatio: (coverageRatio as num).toDouble(),
      median: median,
      p90: p90,
      maximum: maximum,
      band: band,
    );
  }

  static bool _strongerSector(LightDomeSector candidate, LightDomeSector current) {
    if (candidate.p90! != current.p90!) return candidate.p90! > current.p90!;
    if (candidate.maximum! != current.maximum!) {
      return candidate.maximum! > current.maximum!;
    }
    return candidate.sampleCount > current.sampleCount;
  }

  static RelativeRadianceBand _bandFor(double radiance) {
    if (radiance <= 0.15) return RelativeRadianceBand.veryDark;
    if (radiance <= 0.5) return RelativeRadianceBand.dark;
    if (radiance <= 2) return RelativeRadianceBand.moderate;
    if (radiance <= 10) return RelativeRadianceBand.bright;
    return RelativeRadianceBand.veryBright;
  }

  static double? _optionalRadiance(Object? value) {
    if (value == null) return null;
    if (!_finiteIn(value, 0, 1000000)) {
      throw const FormatException('Invalid radiance value');
    }
    return (value as num).toDouble();
  }

  static RelativeRadianceBand? _optionalBand(Object? value) {
    if (value == null) return null;
    return RelativeRadianceBand.values
            .where((item) => item.name == value)
            .firstOrNull ??
        (throw const FormatException('Invalid radiance band'));
  }

  static LightDomeDirection _direction(Object? value) =>
      _optionalDirection(value) ??
      (throw const FormatException('Invalid light-dome direction'));

  static LightDomeDirection? _optionalDirection(Object? value) {
    if (value == null) return null;
    return LightDomeDirection.values
            .where((item) => item.name == value)
            .firstOrNull ??
        (throw const FormatException('Invalid light-dome direction'));
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

  static bool _finiteEquals(Object? value, double expected) =>
      value is num && value.isFinite && (value.toDouble() - expected).abs() < 0.0001;

  static bool _finiteIn(Object? value, double minimum, double maximum) =>
      value is num && value.isFinite && value >= minimum && value <= maximum;
}

class _RadianceSummary {
  const _RadianceSummary({
    required this.sampleCount,
    required this.coverageRatio,
    required this.median,
    required this.p90,
    required this.maximum,
    required this.band,
  });

  final int sampleCount;
  final double coverageRatio;
  final double? median;
  final double? p90;
  final double? maximum;
  final RelativeRadianceBand? band;
}
