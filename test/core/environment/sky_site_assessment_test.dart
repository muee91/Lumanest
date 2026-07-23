import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/sky_site_assessment.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';

Map<String, Object?> _body() => {
  'contractVersion': 4,
  'requestedCoordinate': {
    'latitude': 30.2502,
    'longitude': 120.1502,
    'system': 'wgs84',
  },
  'terrain': <String, Object?>{},
  'nightSkyBackground': <String, Object?>{},
  'generatedAt': '2026-07-23T16:00:01.000Z',
  'observedAt': '2026-07-23T16:00:00.000Z',
  'terrainHorizon': {
    'status': 'ready',
    'algorithmVersion': 'terrain-horizon-radial.1',
    'datasetRevision': 'copernicus-glo30-2024-r1',
    'resolutionMeters': 30,
    'observer': {
      'elevationMeters': 3200,
      'sampledCoordinate': {
        'latitude': 30.25,
        'longitude': 120.15,
        'system': 'wgs84',
      },
      'heightMeters': 1.7,
    },
    'azimuthStepDegrees': 5,
    'maximumDistanceKm': 40,
    'sampleSpacingMeters': 60,
    'refractionCoefficient': 0.13,
    'coverageRatio': 0.96,
    'samples': List<Map<String, Object?>>.generate(
      72,
      (index) => {
        'azimuthDegrees': index * 5,
        'horizonAltitudeDegrees': 4.0,
        'obstructionDistanceKm': 6.0,
        'obstructionElevationMeters': 3600.0,
        'coverageRatio': 0.96,
      },
    ),
    'sampledCoordinate': {
      'latitude': 30.25,
      'longitude': 120.15,
      'system': 'wgs84',
    },
    'generatedAt': '2026-07-23T16:00:01.000Z',
    'expiresAt': '2026-08-22T16:00:01.000Z',
    'cacheStatus': 'miss',
    'source': {
      'id': 'copernicus-dem-glo30',
      'revision': 'copernicus-glo30-2024-r1',
      'attribution': 'Copernicus DEM GLO-30',
    },
  },
  'skySiteAssessment': {
    'status': 'ready',
    'conditionBand': 'conditional',
    'algorithmVersion': 'sky-site-assessment.1',
    'observedAt': '2026-07-23T16:00:00.000Z',
    'geometry': {
      'galacticCenter': {
        'azimuthDegrees': 142.0,
        'altitudeDegrees': 18.2,
        'modelVersion': 'iau-galactic-center-j2000.1',
      },
      'sun': {
        'azimuthDegrees': 10.0,
        'altitudeDegrees': -25.0,
        'modelVersion': 'solar-position-low-precision.1',
      },
      'astronomicalNight': true,
    },
    'terrain': {
      'status': 'ready',
      'horizonAltitudeDegrees': 4.0,
      'clearanceDegrees': 14.2,
      'obstructionDistanceKm': 6.0,
      'obstructionElevationMeters': 3600.0,
      'coverageRatio': 0.96,
      'sourceRevision': 'copernicus-glo30-2024-r1',
      'algorithmVersion': 'terrain-horizon-radial.1',
    },
    'lightPollution': {
      'status': 'ready',
      'direction': 'southeast',
      'azimuthDegrees': 142.0,
      'p90': 5.0,
      'relativeRadianceBand': 'bright',
      'coverageRatio': 0.9,
      'dominantDirection': 'southeast',
      'dominantAzimuthDegrees': 135.0,
      'dominantAngularSeparationDegrees': 7.0,
    },
    'limitations': ['directional_light_pollution_high'],
  },
};

void main() {
  test('parses terrain horizon and direction-aware assessment', () {
    final envelope = SkySiteAssessmentEnvelope.fromJson(_body());

    expect(envelope.terrainHorizon.samples, hasLength(72));
    expect(envelope.terrainHorizon.status, SiteFactStatus.ready);
    expect(envelope.assessment.conditionBand, SkySiteConditionBand.conditional);
    expect(
      envelope.assessment.geometry?.galacticCenter.azimuthDegrees,
      142,
    );
    expect(
      envelope.assessment.lightPollution.direction,
      LightDomeDirection.southeast,
    );
    expect(
      envelope.assessment.limitations,
      [SkySiteLimitation.directionalLightPollutionHigh],
    );
  });

  test('rejects a mismatched assessment timestamp', () {
    final body = _body();
    final assessment = Map<String, Object?>.from(
      body['skySiteAssessment']! as Map<String, Object?>,
    )..['observedAt'] = '2026-07-23T16:01:00.000Z';
    body['skySiteAssessment'] = assessment;

    expect(
      () => SkySiteAssessmentEnvelope.fromJson(body),
      throwsFormatException,
    );
  });
}
