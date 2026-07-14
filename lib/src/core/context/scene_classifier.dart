import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';

enum SceneEvidenceSource { none, amapSemanticEntities }

class SceneEvidence {
  const SceneEvidence({
    this.urban = false,
    this.waterBody = false,
    this.mountainous = false,
    this.aridLand = false,
    this.settlement = false,
    this.driving = false,
    this.hiking = false,
    this.source = SceneEvidenceSource.none,
  });

  final bool urban;
  final bool waterBody;
  final bool mountainous;
  final bool aridLand;
  final bool settlement;
  final bool driving;
  final bool hiking;
  final SceneEvidenceSource source;
}

class SceneClassifier {
  const SceneClassifier();

  /// Classifies the scene. When [route] is active (driving or hiking) it takes
  /// precedence over geo evidence, mirroring the server-side contract where
  /// `route.mode=X && route.stage=active` determines the DRIVING/HIKING scene.
  /// Planned or paused routes do not override the geo-derived scene.
  SceneType classify(
    SceneEvidence evidence, {
    RouteContextState route = RouteContextState.none,
  }) {
    if (route.isActive) {
      if (route.mode == ContextRouteMode.hiking) return SceneType.hiking;
      if (route.mode == ContextRouteMode.driving) return SceneType.driving;
    }
    if (evidence.hiking) return SceneType.hiking;
    if (evidence.driving) return SceneType.driving;
    if (evidence.waterBody) return SceneType.lake;
    if (evidence.mountainous) return SceneType.mountain;
    if (evidence.aridLand) return SceneType.desert;
    if (evidence.settlement) return SceneType.village;
    if (evidence.urban) return SceneType.city;
    return SceneType.unknown;
  }
}
