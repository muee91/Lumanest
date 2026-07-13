import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';

void main() {
  test('classifies all supported scenes only from explicit evidence', () {
    const classifier = SceneClassifier();

    expect(
      classifier.classify(const SceneEvidence(urban: true)),
      SceneType.city,
    );
    expect(
      classifier.classify(const SceneEvidence(waterBody: true)),
      SceneType.lake,
    );
    expect(
      classifier.classify(const SceneEvidence(mountainous: true)),
      SceneType.mountain,
    );
    expect(
      classifier.classify(const SceneEvidence(aridLand: true)),
      SceneType.desert,
    );
    expect(
      classifier.classify(const SceneEvidence(settlement: true)),
      SceneType.village,
    );
  });

  test('does not infer a scene without reliable evidence', () {
    expect(
      const SceneClassifier().classify(const SceneEvidence()),
      SceneType.unknown,
    );
  });

  test('active travel state takes precedence over terrain evidence', () {
    const classifier = SceneClassifier();
    expect(
      classifier.classify(const SceneEvidence(waterBody: true, driving: true)),
      SceneType.driving,
    );
    expect(
      classifier.classify(const SceneEvidence(mountainous: true, hiking: true)),
      SceneType.hiking,
    );
  });
}
