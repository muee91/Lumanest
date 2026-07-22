import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/features/explore/application/exploration_scene_profile_resolver.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';

Map<String, Object?> _readyContract({
  String terrainRevision = 'copernicus-dem-glo90-2021',
  String skyRevision = 'eog-v2.2-2024-median-masked-r1',
  String? skySourceRevision,
}) => {
  'contractVersion': 2,
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
  test('parses independently cached terrain and VIIRS facts', () {
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
