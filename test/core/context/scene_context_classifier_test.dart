import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';

void main() {
  test('activity never replaces the physical scene', () {
    final context = SceneContextClassifier.classify(
      facets: const {SceneFacet.lake, SceneFacet.reflectiveSurface},
      activity: ActivityState.driving,
    );

    expect(context.primaryScene, PrimaryScene.inlandWater);
    expect(context.activity, ActivityState.driving);
    expect(context.facets, contains(SceneFacet.reflectiveSurface));
  });

  test('uses the fixed scene score and tie order', () {
    final context = SceneContextClassifier.classify(
      facets: const {
        SceneFacet.reviewedPeak,
        SceneFacet.coast,
        SceneFacet.wetland,
      },
    );

    expect(context.scores[PrimaryScene.mountain], 60);
    expect(context.scores[PrimaryScene.coast], 60);
    expect(context.scores[PrimaryScene.wetland], 60);
    expect(context.primaryScene, PrimaryScene.mountain);
  });

  test('reviewed primary scene overrides automatic scoring at 100', () {
    final context = SceneContextClassifier.classify(
      facets: const {SceneFacet.skyline, SceneFacet.architecture},
      reviewedPrimaryScene: PrimaryScene.village,
    );

    expect(context.primaryScene, PrimaryScene.village);
    expect(context.scores, {PrimaryScene.village: 100});
    expect(context.reviewedOverride, isTrue);
  });

  test('keeps all matched facets while selecting one primary scene', () {
    final context = SceneContextClassifier.classify(
      facets: SceneFacet.values,
      activity: ActivityState.hiking,
    );

    expect(context.facets, hasLength(24));
    expect(context.primaryScene, PrimaryScene.mountain);
    expect(context.activity, ActivityState.hiking);
  });
}
