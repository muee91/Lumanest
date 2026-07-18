import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';

void main() {
  test('decodes the generated catalog into bounded domain enums', () {
    final catalog = OpportunityCatalog.current;
    final waterEvening = catalog.byId['session.water.evening']!;

    expect(catalog.version, 1);
    expect(catalog.definitions, hasLength(48));
    expect(catalog.coreDefinitions, hasLength(16));
    expect(waterEvening.catalogTier, CatalogTier.core);
    expect(waterEvening.coreCapability, CoreCapabilityState.available);
    expect(waterEvening.modelType, OpportunityModelType.shootingSession);
    expect(waterEvening.family, OpportunityFamily.water);
    expect(waterEvening.primaryScenes, contains(PrimaryScene.inlandWater));
    expect(waterEvening.sceneFacets, contains(SceneFacet.reflectiveSurface));
    expect(waterEvening.requiredEvidence, contains(EvidenceKind.wind));
    expect(waterEvening.primaryAction, ContextAction.openShootingWindow);
  });

  test('keeps per-policy evidence TTL instead of one global duration', () {
    final catalog = OpportunityCatalog.current;

    expect(
      catalog.timingById['timing.rainbow']!.evidenceTtl,
      const Duration(minutes: 10),
    );
    expect(
      catalog.timingById['timing.astroMeteor']!.evidenceTtl,
      const Duration(minutes: 60),
    );
    expect(
      catalog.timingPolicies.map((item) => item.evidenceTtl).toSet().length,
      greaterThan(1),
    );
  });
}
