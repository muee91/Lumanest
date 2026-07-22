import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/features/explore/application/exploration_scene_profile_resolver.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';

void main() {
  test('parses ready terrain and VIIRS facts without calling them Bortle', () {
    final facts = SiteEnvironmentFacts.fromJson({
      'contractVersion': 1,
      'coordinate': {
        'latitude': 30.25,
        'longitude': 120.15,
        'system': 'wgs84',
      },
      'terrain': {
        'status': 'ready',
        'elevationMeters': 126.0,
        'source': {
          'id': 'open-meteo-elevation',
          'dataset': 'Copernicus DEM GLO-90 2021',
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
        'resolutionMeters': 500,
        'source': {
          'id': 'eog-viirs-annual-v2.2',
          'attribution': 'Earth Observation Group',
        },
      },
      'generatedAt': '2026-07-22T12:00:00Z',
      'expiresAt': '2026-07-23T12:00:00Z',
      'cacheStatus': 'miss',
    });

    expect(facts.terrain.elevationMeters, 126);
    expect(
      facts.nightSkyBackground.relativeRadianceBand,
      RelativeRadianceBand.dark,
    );
    expect(facts.nightSkyBackground.isUsable, isTrue);
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
