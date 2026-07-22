import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/features/explore/application/exploration_scene_profile_resolver.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';

const _directions = [
  ('north', 0.0),
  ('northeast', 45.0),
  ('east', 90.0),
  ('southeast', 135.0),
  ('south', 180.0),
  ('southwest', 225.0),
  ('west', 270.0),
  ('northwest', 315.0),
];

Map<String, Object?> _spatialAnalysis({
  String dominantDirection = 'southeast',
  double dominantAzimuthDegrees = 135,
}) => {
  'analysisVersion': 'viirs-spatial-radiance.1',
  'maximumRadiusKm': 20,
  'neighborhoods': [
    {
      'radiusKm': 1,
      'sampleCount': 12,
      'coverageRatio': 1.0,
      'median': 0.1,
      'p90': 0.2,
      'maximum': 0.3,
      'relativeRadianceBand': 'dark',
    },
    {
      'radiusKm': 5,
      'sampleCount': 80,
      'coverageRatio': 0.95,
      'median': 0.2,
      'p90': 0.4,
      'maximum': 1.2,
      'relativeRadianceBand': 'dark',
    },
    {
      'radiusKm': 20,
      'sampleCount': 1200,
      'coverageRatio': 0.9,
      'median': 0.3,
      'p90': 1.5,
      'maximum': 12.0,
      'relativeRadianceBand': 'moderate',
    },
  ],
  'lightDomes': {
    'innerRadiusKm': 1,
    'outerRadiusKm': 20,
    'sectorCount': 8,
    'dominantDirection': dominantDirection,
    'dominantAzimuthDegrees': dominantAzimuthDegrees,
    'sectors': _directions.map((entry) {
      final bright = entry.$1 == 'southeast';
      return {
        'direction': entry.$1,
        'azimuthCenterDegrees': entry.$2,
        'sampleCount': 100,
        'coverageRatio': 0.9,
        'median': bright ? 1.2 : 0.2,
        'p90': bright ? 8.0 : 0.4,
        'maximum': bright ? 12.0 : 0.8,
        'peakDistanceKm': bright ? 14.0 : 8.0,
        'relativeRadianceBand': bright ? 'bright' : 'dark',
      };
    }).toList(),
  },
};

Map<String, Object?> _readyContract({
  String terrainRevision = 'copernicus-dem-glo90-2021',
  String skyRevision = 'eog-v2.2-2024-median-masked-r1',
  String? skySourceRevision,
  Map<String, Object?>? spatialAnalysis,
}) => {
  'contractVersion': 3,
  'requestedCoordinate': {
    'latitude': 30.2502,
    'longitude': 120.1502,
    'system': 'wgs84',
  },
  'terrain': {
    'status': 'ready',
    'elevationMeters': 126.0,
    'sampledCoordinate': {
      'latitude': 30.25,
      'longitude': 120.15,
      'system': 'wgs84',
    },
    'generatedAt': '2026-07-22T12:00:00Z',
    'expiresAt': '2026-10-20T12:00:00Z',
    'cacheStatus': 'hit',
    'source': {
      'id': 'open-meteo-elevation',
      'dataset': 'Copernicus DEM GLO-90 2021',
      'revision': terrainRevision,
      'resolutionMeters': 90,
      'attribution': 'Copernicus DEM · Open-Meteo',
    },
  },
  'nightSkyBackground': {
    'status': 'ready',
    'radiance': 0.42,
    'radianceUnit': 'nW/cm2/sr',
    'relativeRadianceBand': 'dark',
    'classificationVersion': 'viirs-relative-radiance.1',
    'datasetYear': 2024,
    'datasetRevision': skyRevision,
    'resolutionMeters': 500,
    'spatialAnalysis': spatialAnalysis ?? _spatialAnalysis(),
    'sampledCoordinate': {
      'latitude': 30.2505,
      'longitude': 120.1505,
      'system': 'wgs84',
    },
    'generatedAt': '2026-07-22T12:00:00Z',
    'expiresAt': '2026-08-21T12:00:00Z',
    'cacheStatus': 'miss',
    'source': {
      'id': 'eog-viirs-annual-v2.2',
      'revision': skySourceRevision ?? skyRevision,
      'attribution': 'Earth Observation Group',
    },
  },
  'generatedAt': '2026-07-22T12:00:00Z',
};

void main() {
  test('parses spatially analyzed VIIRS facts', () {
    final facts = SiteEnvironmentFacts.fromJson(_readyContract());

    expect(facts.requestedCoordinate.latitude, 30.2502);
    expect(facts.terrain.sampledCoordinate.latitude, 30.25);
    expect(facts.terrain.elevationMeters, 126);
    expect(facts.terrain.cacheStatus, 'hit');
    expect(facts.terrain.sourceRevision, 'copernicus-dem-glo90-2021');
    expect(facts.nightSkyBackground.sampledCoordinate.latitude, 30.2505);
    expect(
      facts.nightSkyBackground.relativeRadianceBand,
      RelativeRadianceBand.dark,
    );
    final analysis = facts.nightSkyBackground.spatialAnalysis!;
    expect(
      analysis.neighborhood(20)?.relativeRadianceBand,
      RelativeRadianceBand.moderate,
    );
    expect(
      analysis.lightDomes.dominantDirection,
      LightDomeDirection.southeast,
    );
    expect(analysis.lightDomes.dominantSector?.p90, 8);
    expect(
      analysis.lightDomes.dominantSector?.relativeRadianceBand,
      RelativeRadianceBand.bright,
    );
    expect(
      facts.nightSkyBackground.datasetRevision,
      'eog-v2.2-2024-median-masked-r1',
    );
    expect(facts.nightSkyBackground.cacheStatus, 'miss');
    expect(facts.nightSkyBackground.isUsable, isTrue);
    expect(facts.cacheStatus, 'mixed');
    expect(
      facts.expiresAt,
      DateTime.parse('2026-08-21T12:00:00Z').toUtc(),
    );
  });

  test('rejects a VIIRS source revision that differs from the dataset', () {
    expect(
      () => SiteEnvironmentFacts.fromJson(
        _readyContract(skySourceRevision: 'different-revision'),
      ),
      throwsFormatException,
    );
  });

  test('rejects inconsistent dominant light-dome metadata', () {
    expect(
      () => SiteEnvironmentFacts.fromJson(
        _readyContract(
          spatialAnalysis: _spatialAnalysis(
            dominantDirection: 'west',
            dominantAzimuthDegrees: 270,
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test('maps evidence-backed elevation to conservative altitude bands', () {
    expect(altitudeBandForMeters(null), AltitudeBand.unknown);
    expect(altitudeBandForMeters(999), AltitudeBand.low);
    expect(altitudeBandForMeters(1000), AltitudeBand.moderate);
    expect(altitudeBandForMeters(2499), AltitudeBand.moderate);
    expect(altitudeBandForMeters(2500), AltitudeBand.high);
    expect(altitudeBandForMeters(3499), AltitudeBand.high);
    expect(altitudeBandForMeters(3500), AltitudeBand.veryHigh);
  });
}
