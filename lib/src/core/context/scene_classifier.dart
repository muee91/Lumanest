import 'package:luma_nest/src/core/context/context_snapshot.dart';

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

  /// Classifies only the physical scene. Activity is carried independently by
  /// [SceneContext.activity] and can never replace the place around the user.
  SceneType classify(SceneEvidence evidence) {
    if (evidence.waterBody) return SceneType.lake;
    if (evidence.mountainous) return SceneType.mountain;
    if (evidence.aridLand) return SceneType.desert;
    if (evidence.settlement) return SceneType.village;
    if (evidence.urban) return SceneType.city;
    return SceneType.unknown;
  }
}
