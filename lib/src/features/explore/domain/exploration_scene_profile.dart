import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';

enum SettlementType {
  unknown,
  none,
  metropolitan,
  urbanDistrict,
  historicDistrict,
  historicTown,
  village,
  pastoralSettlement,
  scenicArea,
}

enum RemotenessLevel { unknown, connected, edge, remote, extreme }

enum AltitudeBand { low, moderate, high, veryHigh, unknown }

enum PoiDensityBand { unknown, dense, normal, sparse, verySparse }

/// A transport-safe, evidence-aware view of the current exploration setting.
///
/// This is deliberately not a second scene classifier. [physicalScene],
/// [facets], mobility and route stage originate from ContextSnapshot; the
/// remaining dimensions stay conservative until backed by a reviewed source.
class ExplorationSceneProfile {
  ExplorationSceneProfile({
    required this.physicalScene,
    required Iterable<SceneFacet> facets,
    required this.settlement,
    required this.remoteness,
    required this.altitude,
    required this.poiDensity,
    required this.mobility,
    required this.routeStage,
  }) : facets = Set.unmodifiable(facets);

  final PrimaryScene physicalScene;
  final Set<SceneFacet> facets;
  final SettlementType settlement;
  final RemotenessLevel remoteness;
  final AltitudeBand altitude;
  final PoiDensityBand poiDensity;
  final ActivityState mobility;
  final ContextRouteStage routeStage;

  Map<String, Object?> toJson() => {
    'physicalScene': physicalScene.name,
    'facets': facets.map((item) => item.name).toList(growable: false),
    'settlement': settlement.name,
    'remoteness': remoteness.name,
    'altitude': altitude.name,
    'poiDensity': poiDensity.name,
    'mobility': mobility.name,
    'routeStage': routeStage.name,
  };
}
