import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/core/environment/site_environment_providers.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';

AltitudeBand altitudeBandForMeters(double? elevationMeters) {
  if (elevationMeters == null || !elevationMeters.isFinite) {
    return AltitudeBand.unknown;
  }
  if (elevationMeters < 1000) return AltitudeBand.low;
  if (elevationMeters < 2500) return AltitudeBand.moderate;
  if (elevationMeters < 3500) return AltitudeBand.high;
  return AltitudeBand.veryHigh;
}

/// Resolves only evidence-backed facts. Protected-area, infrastructure and
/// remoteness dimensions stay `unknown`; this provider must never infer them
/// from a place name. Elevation comes from the supplementary Copernicus DEM
/// fact and degrades independently when that source is unavailable.
ExplorationSceneProfile resolveExplorationSceneProfile(
  ContextSnapshot snapshot, {
  SiteEnvironmentFacts? siteFacts,
}) {
  final scene = snapshot.resolvedSceneContext;
  final settlement = switch (scene.primaryScene) {
    PrimaryScene.urban when scene.facets.contains(SceneFacet.oldTown) =>
      SettlementType.historicDistrict,
    PrimaryScene.urban => SettlementType.urbanDistrict,
    PrimaryScene.village when scene.facets.contains(SceneFacet.oldTown) =>
      SettlementType.historicTown,
    PrimaryScene.village => SettlementType.village,
    _ => SettlementType.unknown,
  };
  final elevation = siteFacts?.terrain.status == SiteFactStatus.ready
      ? siteFacts?.terrain.elevationMeters
      : null;
  return ExplorationSceneProfile(
    physicalScene: scene.primaryScene,
    facets: scene.facets,
    settlement: settlement,
    remoteness: RemotenessLevel.unknown,
    altitude: altitudeBandForMeters(elevation),
    poiDensity: PoiDensityBand.unknown,
    mobility: scene.activity,
    routeStage: snapshot.routeStage,
  );
}

final explorationSceneProfileProvider = FutureProvider<ExplorationSceneProfile>(
  (ref) async {
    final snapshot = await ref.watch(environmentSnapshotProvider.future);
    // Starting this provider is intentional, but the current Region Brief load
    // must not wait for a supplementary DEM/VIIRS network request. Riverpod
    // rebuilds this profile automatically when the site facts arrive.
    final siteFacts = ref.watch(siteEnvironmentFactsProvider).asData?.value;
    return resolveExplorationSceneProfile(snapshot, siteFacts: siteFacts);
  },
);
