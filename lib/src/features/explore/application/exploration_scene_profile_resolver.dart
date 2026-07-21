import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';

/// Resolves only facts already present in ContextSnapshot. Values requiring
/// elevation, protected-area or infrastructure evidence stay `unknown`; this
/// provider must never infer safety-relevant facts from a place name.
ExplorationSceneProfile resolveExplorationSceneProfile(
  ContextSnapshot snapshot,
) {
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
  return ExplorationSceneProfile(
    physicalScene: scene.primaryScene,
    facets: scene.facets,
    settlement: settlement,
    remoteness: RemotenessLevel.unknown,
    altitude: AltitudeBand.unknown,
    poiDensity: PoiDensityBand.unknown,
    mobility: scene.activity,
    routeStage: snapshot.routeStage,
  );
}

final explorationSceneProfileProvider = FutureProvider<ExplorationSceneProfile>(
  (ref) async {
    final snapshot = await ref.watch(environmentSnapshotProvider.future);
    return resolveExplorationSceneProfile(snapshot);
  },
);
