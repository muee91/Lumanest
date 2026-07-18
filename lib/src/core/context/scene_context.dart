import 'dart:collection';

/// The physical scene around the user. Activity and route state are modeled
/// separately so driving or hiking can never erase the actual place.
enum PrimaryScene {
  unknown,
  urban,
  village,
  mountain,
  plateau,
  desert,
  forest,
  inlandWater,
  coast,
  wetland,
}

enum SceneFacet {
  lake,
  river,
  reservoir,
  wetland,
  coast,
  tidalFlat,
  waterfall,
  snowCover,
  glacier,
  canyon,
  dune,
  grassland,
  forest,
  bambooForest,
  skyline,
  architecture,
  oldTown,
  villageStreet,
  openRoad,
  openHorizon,
  darkSky,
  reviewedPeak,
  reviewedViewpoint,
  reflectiveSurface,
}

enum ActivityState { stationary, walking, hiking, driving }

class SceneContext {
  SceneContext({
    required this.primaryScene,
    required Iterable<SceneFacet> facets,
    required this.activity,
    Map<PrimaryScene, int> scores = const <PrimaryScene, int>{},
    this.reviewedOverride = false,
  }) : facets = Set.unmodifiable(facets),
       scores = UnmodifiableMapView(Map<PrimaryScene, int>.of(scores));

  final PrimaryScene primaryScene;
  final Set<SceneFacet> facets;
  final ActivityState activity;
  final Map<PrimaryScene, int> scores;
  final bool reviewedOverride;

  bool hasFacet(SceneFacet facet) => facets.contains(facet);

  SceneContext copyWith({
    PrimaryScene? primaryScene,
    Iterable<SceneFacet>? facets,
    ActivityState? activity,
    Map<PrimaryScene, int>? scores,
    bool? reviewedOverride,
  }) {
    return SceneContext(
      primaryScene: primaryScene ?? this.primaryScene,
      facets: facets ?? this.facets,
      activity: activity ?? this.activity,
      scores: scores ?? this.scores,
      reviewedOverride: reviewedOverride ?? this.reviewedOverride,
    );
  }
}

abstract final class SceneContextClassifier {
  static const _tieOrder = <PrimaryScene>[
    PrimaryScene.mountain,
    PrimaryScene.coast,
    PrimaryScene.wetland,
    PrimaryScene.inlandWater,
    PrimaryScene.plateau,
    PrimaryScene.desert,
    PrimaryScene.forest,
    PrimaryScene.village,
    PrimaryScene.urban,
    PrimaryScene.unknown,
  ];

  static SceneContext classify({
    required Iterable<SceneFacet> facets,
    ActivityState activity = ActivityState.stationary,
    PrimaryScene? reviewedPrimaryScene,
  }) {
    final facetSet = Set<SceneFacet>.unmodifiable(facets);
    if (reviewedPrimaryScene != null &&
        reviewedPrimaryScene != PrimaryScene.unknown) {
      return SceneContext(
        primaryScene: reviewedPrimaryScene,
        facets: facetSet,
        activity: activity,
        scores: <PrimaryScene, int>{reviewedPrimaryScene: 100},
        reviewedOverride: true,
      );
    }

    final scores = <PrimaryScene, int>{};

    void score(PrimaryScene scene, int value) {
      final current = scores[scene] ?? 0;
      if (value > current) scores[scene] = value;
    }

    if (facetSet.intersection(const {
      SceneFacet.reviewedPeak,
      SceneFacet.glacier,
      SceneFacet.canyon,
    }).isNotEmpty) {
      score(PrimaryScene.mountain, 60);
    }
    if (facetSet.intersection(const {
      SceneFacet.coast,
      SceneFacet.tidalFlat,
    }).isNotEmpty) {
      score(PrimaryScene.coast, 60);
    }
    if (facetSet.contains(SceneFacet.wetland)) {
      score(PrimaryScene.wetland, 60);
    }
    if (facetSet.contains(SceneFacet.dune)) {
      score(PrimaryScene.desert, 60);
    }
    if (facetSet.contains(SceneFacet.grassland)) {
      score(PrimaryScene.plateau, 55);
    }
    if (facetSet.intersection(const {
      SceneFacet.forest,
      SceneFacet.bambooForest,
    }).isNotEmpty) {
      score(PrimaryScene.forest, 55);
    }
    if (facetSet.intersection(const {
      SceneFacet.lake,
      SceneFacet.reservoir,
    }).isNotEmpty) {
      score(PrimaryScene.inlandWater, 55);
    }
    if (facetSet.intersection(const {
      SceneFacet.oldTown,
      SceneFacet.villageStreet,
    }).isNotEmpty) {
      score(PrimaryScene.village, 50);
    }
    if (facetSet.intersection(const {
      SceneFacet.skyline,
      SceneFacet.architecture,
    }).isNotEmpty) {
      score(PrimaryScene.urban, 45);
    }
    if (facetSet.contains(SceneFacet.river)) {
      score(PrimaryScene.inlandWater, 35);
    }

    final primary = scores.isEmpty
        ? PrimaryScene.unknown
        : _tieOrder.firstWhere(
            (scene) => (scores[scene] ?? 0) == _maximumScore(scores),
            orElse: () => PrimaryScene.unknown,
          );
    return SceneContext(
      primaryScene: primary,
      facets: facetSet,
      activity: activity,
      scores: scores,
    );
  }

  static int _maximumScore(Map<PrimaryScene, int> scores) {
    if (scores.isEmpty) return 0;
    return scores.values.reduce((left, right) => left > right ? left : right);
  }
}
