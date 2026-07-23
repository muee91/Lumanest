import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

enum SkySiteAssessmentStatus { ready, unavailable }

enum SkySiteConditionBand {
  favorable,
  conditional,
  unavailable,
  insufficientData,
}

enum SkySiteLimitation {
  astronomicalGeometryUnavailable,
  notAstronomicalNight,
  galacticCenterBelowGeometricHorizon,
  terrainHorizonUnavailable,
  terrainCoverageLimited,
  galacticCenterTerrainBlocked,
  terrainClearanceLimited,
  directionalLightPollutionUnavailable,
  lightPollutionCoverageLimited,
  directionalLightPollutionHigh,
  directionalLightPollutionModerate,
}

const _limitationNames = <String, SkySiteLimitation>{
  'astronomical_geometry_unavailable':
      SkySiteLimitation.astronomicalGeometryUnavailable,
  'not_astronomical_night': SkySiteLimitation.notAstronomicalNight,
  'galactic_center_below_geometric_horizon':
      SkySiteLimitation.galacticCenterBelowGeometricHorizon,
  'terrain_horizon_unavailable': SkySiteLimitation.terrainHorizonUnavailable,
  'terrain_coverage_limited': SkySiteLimitation.terrainCoverageLimited,
  'galactic_center_terrain_blocked':
      SkySiteLimitation.galacticCenterTerrainBlocked,
  'terrain_clearance_limited': SkySiteLimitation.terrainClearanceLimited,
  'directional_light_pollution_unavailable':
      SkySiteLimitation.directionalLightPollutionUnavailable,
  'light_pollution_coverage_limited':
      SkySiteLimitation.lightPollutionCoverageLimited,
  'directional_light_pollution_high':
      SkySiteLimitation.directionalLightPollutionHigh,
  'directional_light_pollution_moderate':
      SkySiteLimitation.directionalLightPollutionModerate,
};

class SkyBodyPosition {
  const SkyBodyPosition({
    required this.azimuthDegrees,
    required this.altitudeDegrees,
    required this.modelVersion,
  });

  final double azimuthDegrees;
  final double altitudeDegrees;
  final String modelVersion;
}

class SkySiteGeometry {
  const SkySiteGeometry({
    required this.galacticCenter,
    required this.sun,
    required this.astronomicalNight,
  });

  final SkyBodyPosition galacticCenter;
  final SkyBodyPosition sun;
  final bool astronomicalNight;
}

class TerrainHorizonSample {
  const TerrainHorizonSample({
    required this.azimuthDegrees,
    required this.horizonAltitudeDegrees,
    required this.obstructionDistanceKm,
    required this.obstructionElevationMeters,
    required this.coverageRatio,
  });

  final int azimuthDegrees;
  final double? horizonAltitudeDegrees;
  final double? obstructionDistanceKm;
  final double? obstructionElevationMeters;
  final double coverageRatio;
}

class TerrainHorizonFact {
  const TerrainHorizonFact({
    required this.status,
    required this.algorithmVersion,
    required this.datasetRevision,
    required this.resolutionMeters,
    required this.observerElevationMeters,
    required this.observerSampledCoordinate,
    required this.observerHeightMeters,
    required this.azimuthStepDegrees,
    required this.maximumDistanceKm,
    required this.sampleSpacingMeters,
    required this.refractionCoefficient,
    required this.coverageRatio,
    required this.samples,
    required this.sampledCoordinate,
    required this.generatedAt,
    required this.expiresAt,
    required this.cacheStatus,
    required this.sourceId,
    required this.attribution,
  });

  final SiteFactStatus status;
  final String algorithmVersion;
  final String? datasetRevision;
  final double? resolutionMeters;
  final double? observerElevationMeters;
  final GeoPoint? observerSampledCoordinate;
  final double? observerHeightMeters;
  final int azimuthStepDegrees;
  final double maximumDistanceKm;
  final double? sampleSpacingMeters;
  final double refractionCoefficient;
  final double? coverageRatio;
  final List<TerrainHorizonSample> samples;
  final GeoPoint sampledCoordinate;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final String cacheStatus;
  final String? sourceId;
  final String? attribution;

  bool get isUsable => status == SiteFactStatus.ready && samples.length == 72;
}

class TerrainDirectionAssessment {
  const TerrainDirectionAssessment({
    required this.status,
    required this.horizonAltitudeDegrees,
    required this.clearanceDegrees,
    required this.obstructionDistanceKm,
    required this.obstructionElevationMeters,
    required this.coverageRatio,
    required this.sourceRevision,
    required this.algorithmVersion,
  });

  final SiteFactStatus status;
  final double? horizonAltitudeDegrees;
  final double? clearanceDegrees;
  final double? obstructionDistanceKm;
  final double? obstructionElevationMeters;
  final double? coverageRatio;
  final String? sourceRevision;
  final String? algorithmVersion;
}

class DirectionalLightAssessment {
  const DirectionalLightAssessment({
    required this.status,
    required this.direction,
    required this.azimuthDegrees,
    required this.p90,
    required this.relativeRadianceBand,
    required this.coverageRatio,
    required this.dominantDirection,
    required this.dominantAzimuthDegrees,
    required this.dominantAngularSeparationDegrees,
  });

  final SiteFactStatus status;
  final LightDomeDirection? direction;
  final double? azimuthDegrees;
  final double? p90;
  final RelativeRadianceBand? relativeRadianceBand;
  final double? coverageRatio;
  final LightDomeDirection? dominantDirection;
  final double? dominantAzimuthDegrees;
  final double? dominantAngularSeparationDegrees;
}

class SkySiteAssessment {
  const SkySiteAssessment({
    required this.status,
    required this.conditionBand,
    required this.algorithmVersion,
    required this.observedAt,
    required this.geometry,
    required this.terrain,
    required this.lightPollution,
    required this.limitations,
  });

  final SkySiteAssessmentStatus status;
  final SkySiteConditionBand conditionBand;
  final String algorithmVersion;
  final DateTime observedAt;
  final SkySiteGeometry? geometry;
  final TerrainDirectionAssessment terrain;
  final DirectionalLightAssessment lightPollution;
  final List<SkySiteLimitation> limitations;
}

class SkySiteAssessmentEnvelope {
  const SkySiteAssessmentEnvelope({
    required this.requestedCoordinate,
    required this.observedAt,
    required this.terrainHorizon,
    required this.assessment,
    required this.generatedAt,
  });

  final GeoPoint requestedCoordinate;
  final DateTime observedAt;
  final TerrainHorizonFact terrainHorizon;
  final SkySiteAssessment assessment;
  final DateTime generatedAt;

  static SkySiteAssessmentEnvelope fromJson(Map<String, Object?> body) {
    const rootKeys = {
      'contractVersion',
      'requestedCoordinate',
      'terrain',
      'nightSkyBackground',
      'generatedAt',
      'observedAt',
      'terrainHorizon',
      'skySiteAssessment',
    };
    if (!_exactKeys(body, rootKeys) || body['contractVersion'] != 4) {
      throw const FormatException('Invalid sky-site assessment contract');
    }
    if (body['terrain'] is! Map || body['nightSkyBackground'] is! Map) {
      throw const FormatException('Missing environment evidence');
    }
    final observedAt = _date(body['observedAt']);
    final assessment = _assessment(_map(body['skySiteAssessment']));
    if (assessment.observedAt != observedAt) {
      throw const FormatException('Sky-site assessment time mismatch');
    }
    return SkySiteAssessmentEnvelope(
      requestedCoordinate: _coordinate(body['requestedCoordinate']),
      observedAt: observedAt,
      terrainHorizon: _terrainHorizon(_map(body['terrainHorizon'])),
      assessment: assessment,
      generatedAt: _date(body['generatedAt']),
    );
  }

  static TerrainHorizonFact _terrainHorizon(Map<String, Object?> value) {
    const keys = {
      'status',
      'algorithmVersion',
      'datasetRevision',
      'resolutionMeters',
      'observer',
      'azimuthStepDegrees',
      'maximumDistanceKm',
      'sampleSpacingMeters',
      'refractionCoefficient',
      'coverageRatio',
      'samples',
      'sampledCoordinate',
      'generatedAt',
      'expiresAt',
      'cacheStatus',
      'source',
    };
    if (!_exactKeys(value, keys) ||
        value['algorithmVersion'] != 'terrain-horizon-radial.1' ||
        value['azimuthStepDegrees'] != 5 ||
        value['maximumDistanceKm'] != 40 ||
        !_finiteIn(value['refractionCoefficient'], 0, 0.3)) {
      throw const FormatException('Invalid terrain horizon fact');
    }
    final status = _siteStatus(value['status']);
    final generatedAt = _date(value['generatedAt']);
    final expiresAt = _date(value['expiresAt']);
    if (!expiresAt.isAfter(generatedAt)) {
      throw const FormatException('Invalid terrain horizon freshness');
    }
    final sampleValues = value['samples'];
    if (sampleValues is! List) {
      throw const FormatException('Invalid terrain horizon samples');
    }
    final samples = <TerrainHorizonSample>[];
    for (var index = 0; index < sampleValues.length; index += 1) {
      final sample = _map(sampleValues[index]);
      const sampleKeys = {
        'azimuthDegrees',
        'horizonAltitudeDegrees',
        'obstructionDistanceKm',
        'obstructionElevationMeters',
        'coverageRatio',
      };
      if (!_exactKeys(sample, sampleKeys) ||
          sample['azimuthDegrees'] != index * 5 ||
          !_finiteIn(sample['coverageRatio'], 0, 1)) {
        throw const FormatException('Invalid terrain horizon sample');
      }
      final altitude = sample['horizonAltitudeDegrees'];
      final distance = sample['obstructionDistanceKm'];
      final elevation = sample['obstructionElevationMeters'];
      final absent = altitude == null && distance == null && elevation == null;
      final present = _finiteIn(altitude, -90, 90) &&
          _finiteIn(distance, 0.03, 40) &&
          _finiteIn(elevation, -500, 9000);
      if (!absent && !present) {
        throw const FormatException('Invalid terrain obstruction');
      }
      samples.add(
        TerrainHorizonSample(
          azimuthDegrees: sample['azimuthDegrees']! as int,
          horizonAltitudeDegrees: (altitude as num?)?.toDouble(),
          obstructionDistanceKm: (distance as num?)?.toDouble(),
          obstructionElevationMeters: (elevation as num?)?.toDouble(),
          coverageRatio: (sample['coverageRatio']! as num).toDouble(),
        ),
      );
    }

    final observer = value['observer'] == null ? null : _map(value['observer']);
    final source = value['source'] == null ? null : _map(value['source']);
    if (status == SiteFactStatus.ready) {
      if (samples.length != 72 ||
          !_finiteIn(value['resolutionMeters'], 1, 1000) ||
          !_finiteIn(value['sampleSpacingMeters'], 30, 500) ||
          !_finiteIn(value['coverageRatio'], 0, 1) ||
          value['datasetRevision'] is! String ||
          observer == null ||
          !_exactKeys(
            observer,
            const {
              'elevationMeters',
              'sampledCoordinate',
              'heightMeters',
            },
          ) ||
          !_finiteIn(observer['elevationMeters'], -500, 9000) ||
          !_finiteIn(observer['heightMeters'], 0, 20) ||
          source == null ||
          !_exactKeys(source, const {'id', 'revision', 'attribution'}) ||
          source['revision'] != value['datasetRevision']) {
        throw const FormatException('Invalid ready terrain horizon');
      }
    } else if (samples.isNotEmpty ||
        value['datasetRevision'] != null ||
        value['resolutionMeters'] != null ||
        value['sampleSpacingMeters'] != null ||
        value['coverageRatio'] != null ||
        observer != null ||
        source != null) {
      throw const FormatException('Invalid unavailable terrain horizon');
    }

    return TerrainHorizonFact(
      status: status,
      algorithmVersion: value['algorithmVersion']! as String,
      datasetRevision: value['datasetRevision'] as String?,
      resolutionMeters: (value['resolutionMeters'] as num?)?.toDouble(),
      observerElevationMeters:
          (observer?['elevationMeters'] as num?)?.toDouble(),
      observerSampledCoordinate: observer == null
          ? null
          : _coordinate(observer['sampledCoordinate']),
      observerHeightMeters: (observer?['heightMeters'] as num?)?.toDouble(),
      azimuthStepDegrees: value['azimuthStepDegrees']! as int,
      maximumDistanceKm: (value['maximumDistanceKm']! as num).toDouble(),
      sampleSpacingMeters:
          (value['sampleSpacingMeters'] as num?)?.toDouble(),
      refractionCoefficient:
          (value['refractionCoefficient']! as num).toDouble(),
      coverageRatio: (value['coverageRatio'] as num?)?.toDouble(),
      samples: List.unmodifiable(samples),
      sampledCoordinate: _coordinate(value['sampledCoordinate']),
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      cacheStatus: _cacheStatus(value['cacheStatus']),
      sourceId: source?['id'] as String?,
      attribution: source?['attribution'] as String?,
    );
  }

  static SkySiteAssessment _assessment(Map<String, Object?> value) {
    const keys = {
      'status',
      'conditionBand',
      'algorithmVersion',
      'observedAt',
      'geometry',
      'terrain',
      'lightPollution',
      'limitations',
    };
    if (!_exactKeys(value, keys) ||
        value['algorithmVersion'] != 'sky-site-assessment.1') {
      throw const FormatException('Invalid sky-site assessment');
    }
    final status = _assessmentStatus(value['status']);
    final geometry = value['geometry'] == null
        ? null
        : _geometry(_map(value['geometry']));
    if (status == SkySiteAssessmentStatus.ready && geometry == null) {
      throw const FormatException('Missing astronomical geometry');
    }
    final limitationValues = value['limitations'];
    if (limitationValues is! List || limitationValues.length > 16) {
      throw const FormatException('Invalid sky-site limitations');
    }
    final limitations = <SkySiteLimitation>[];
    for (final item in limitationValues) {
      final limitation = _limitationNames[item];
      if (limitation == null) {
        throw const FormatException('Unknown sky-site limitation');
      }
      limitations.add(limitation);
    }
    return SkySiteAssessment(
      status: status,
      conditionBand: _conditionBand(value['conditionBand']),
      algorithmVersion: value['algorithmVersion']! as String,
      observedAt: _date(value['observedAt']),
      geometry: geometry,
      terrain: _terrainDirection(_map(value['terrain'])),
      lightPollution: _directionalLight(_map(value['lightPollution'])),
      limitations: List.unmodifiable(limitations),
    );
  }

  static SkySiteGeometry _geometry(Map<String, Object?> value) {
    if (!_exactKeys(
          value,
          const {'galacticCenter', 'sun', 'astronomicalNight'},
        ) ||
        value['astronomicalNight'] is! bool) {
      throw const FormatException('Invalid sky geometry');
    }
    return SkySiteGeometry(
      galacticCenter: _bodyPosition(_map(value['galacticCenter'])),
      sun: _bodyPosition(_map(value['sun'])),
      astronomicalNight: value['astronomicalNight']! as bool,
    );
  }

  static SkyBodyPosition _bodyPosition(Map<String, Object?> value) {
    if (!_exactKeys(
          value,
          const {'azimuthDegrees', 'altitudeDegrees', 'modelVersion'},
        ) ||
        !_finiteIn(value['azimuthDegrees'], 0, 360) ||
        !_finiteIn(value['altitudeDegrees'], -90, 90) ||
        value['modelVersion'] is! String) {
      throw const FormatException('Invalid sky body position');
    }
    return SkyBodyPosition(
      azimuthDegrees: (value['azimuthDegrees']! as num).toDouble(),
      altitudeDegrees: (value['altitudeDegrees']! as num).toDouble(),
      modelVersion: value['modelVersion']! as String,
    );
  }

  static TerrainDirectionAssessment _terrainDirection(
    Map<String, Object?> value,
  ) {
    final status = _siteStatus(value['status']);
    if (status != SiteFactStatus.ready) {
      if (!_exactKeys(value, const {'status'})) {
        throw const FormatException('Invalid unavailable terrain assessment');
      }
      return TerrainDirectionAssessment(
        status: status,
        horizonAltitudeDegrees: null,
        clearanceDegrees: null,
        obstructionDistanceKm: null,
        obstructionElevationMeters: null,
        coverageRatio: null,
        sourceRevision: null,
        algorithmVersion: null,
      );
    }
    const keys = {
      'status',
      'horizonAltitudeDegrees',
      'clearanceDegrees',
      'obstructionDistanceKm',
      'obstructionElevationMeters',
      'coverageRatio',
      'sourceRevision',
      'algorithmVersion',
    };
    if (!_exactKeys(value, keys) ||
        !_finiteIn(value['horizonAltitudeDegrees'], -90, 90) ||
        !_finiteIn(value['clearanceDegrees'], -180, 180) ||
        !_finiteIn(value['obstructionDistanceKm'], 0.03, 40) ||
        !_finiteIn(value['obstructionElevationMeters'], -500, 9000) ||
        !_finiteIn(value['coverageRatio'], 0, 1) ||
        value['sourceRevision'] is! String ||
        value['algorithmVersion'] != 'terrain-horizon-radial.1') {
      throw const FormatException('Invalid ready terrain assessment');
    }
    return TerrainDirectionAssessment(
      status: status,
      horizonAltitudeDegrees:
          (value['horizonAltitudeDegrees']! as num).toDouble(),
      clearanceDegrees: (value['clearanceDegrees']! as num).toDouble(),
      obstructionDistanceKm:
          (value['obstructionDistanceKm']! as num).toDouble(),
      obstructionElevationMeters:
          (value['obstructionElevationMeters']! as num).toDouble(),
      coverageRatio: (value['coverageRatio']! as num).toDouble(),
      sourceRevision: value['sourceRevision']! as String,
      algorithmVersion: value['algorithmVersion']! as String,
    );
  }

  static DirectionalLightAssessment _directionalLight(
    Map<String, Object?> value,
  ) {
    final status = _siteStatus(value['status']);
    if (status != SiteFactStatus.ready) {
      if (!_exactKeys(value, const {'status'})) {
        throw const FormatException('Invalid unavailable light assessment');
      }
      return DirectionalLightAssessment(
        status: status,
        direction: null,
        azimuthDegrees: null,
        p90: null,
        relativeRadianceBand: null,
        coverageRatio: null,
        dominantDirection: null,
        dominantAzimuthDegrees: null,
        dominantAngularSeparationDegrees: null,
      );
    }
    const keys = {
      'status',
      'direction',
      'azimuthDegrees',
      'p90',
      'relativeRadianceBand',
      'coverageRatio',
      'dominantDirection',
      'dominantAzimuthDegrees',
      'dominantAngularSeparationDegrees',
    };
    if (!_exactKeys(value, keys) ||
        !_finiteIn(value['azimuthDegrees'], 0, 360) ||
        !_finiteIn(value['p90'], 0, 1000000) ||
        !_finiteIn(value['coverageRatio'], 0, 1) ||
        !_finiteIn(value['dominantAzimuthDegrees'], 0, 360) ||
        !_finiteIn(value['dominantAngularSeparationDegrees'], 0, 180)) {
      throw const FormatException('Invalid ready light assessment');
    }
    return DirectionalLightAssessment(
      status: status,
      direction: _lightDirection(value['direction']),
      azimuthDegrees: (value['azimuthDegrees']! as num).toDouble(),
      p90: (value['p90']! as num).toDouble(),
      relativeRadianceBand: _radianceBand(value['relativeRadianceBand']),
      coverageRatio: (value['coverageRatio']! as num).toDouble(),
      dominantDirection: _lightDirection(value['dominantDirection']),
      dominantAzimuthDegrees:
          (value['dominantAzimuthDegrees']! as num).toDouble(),
      dominantAngularSeparationDegrees:
          (value['dominantAngularSeparationDegrees']! as num).toDouble(),
    );
  }

  static SiteFactStatus _siteStatus(Object? value) =>
      _enumByName(SiteFactStatus.values, value, 'site fact status');

  static SkySiteAssessmentStatus _assessmentStatus(Object? value) =>
      _enumByName(
        SkySiteAssessmentStatus.values,
        value,
        'assessment status',
      );

  static SkySiteConditionBand _conditionBand(Object? value) => _enumByName(
        SkySiteConditionBand.values,
        value,
        'assessment condition',
      );

  static LightDomeDirection _lightDirection(Object? value) => _enumByName(
        LightDomeDirection.values,
        value,
        'light-dome direction',
      );

  static RelativeRadianceBand _radianceBand(Object? value) => _enumByName(
        RelativeRadianceBand.values,
        value,
        'radiance band',
      );

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? value,
    String label,
  ) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw FormatException('Invalid $label');
  }

  static String _cacheStatus(Object? value) {
    if (value is String &&
        const {'hit', 'miss', 'coalesced'}.contains(value)) {
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
      throw const FormatException('Invalid assessment coordinate');
    }
    return GeoPoint(
      latitude: (coordinate['latitude']! as num).toDouble(),
      longitude: (coordinate['longitude']! as num).toDouble(),
    );
  }

  static DateTime _date(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) throw const FormatException('Invalid assessment time');
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
