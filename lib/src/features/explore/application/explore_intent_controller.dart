import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class ExploreIntentState {
  const ExploreIntentState({
    required this.category,
    this.activeFocus,
    this.creativeIntent,
    this.sceneCategory = NearbyPlaceCategory.viewpoint,
    this.followsScene = true,
  });

  final NearbyPlaceCategory category;
  final ExploreFocus? activeFocus;
  final ExploreCreativeIntent? creativeIntent;
  final NearbyPlaceCategory sceneCategory;
  final bool followsScene;

  bool get hasActiveIntent => activeFocus != null;
}

class ExploreIntentController extends Notifier<ExploreIntentState> {
  @override
  ExploreIntentState build() =>
      const ExploreIntentState(category: NearbyPlaceCategory.viewpoint);

  /// Activates a focus explicitly requested by a Today/Inspiraton action.
  /// A plain Explore route preserves a manual category already chosen by the
  /// user, unless it is clearing an active temporary focus.
  void activate(ExploreFocus focus) {
    if (focus == ExploreFocus.photography) {
      if (!state.hasActiveIntent) return;
      state = ExploreIntentState(
        category: state.sceneCategory,
        sceneCategory: state.sceneCategory,
      );
      return;
    }
    state = ExploreIntentState(
      category: focus.category,
      activeFocus: focus,
      sceneCategory: state.sceneCategory,
    );
  }

  /// A user-picked category or a completed route/search action takes over from
  /// temporary intent without forcing the photography default.
  void complete({required NearbyPlaceCategory category}) {
    state = ExploreIntentState(
      category: category,
      sceneCategory: state.sceneCategory,
      followsScene: false,
    );
  }

  /// A local Explore choice. It only changes which existing nearby query is
  /// used; it does not claim that a photographic condition exists.
  void chooseCreativeIntent(ExploreCreativeIntent intent) {
    state = ExploreIntentState(
      category: intent.category,
      creativeIntent: intent,
      sceneCategory: state.sceneCategory,
      followsScene: false,
    );
  }

  /// Applies a deterministic default layer when the user has not manually
  /// selected a category and no temporary cross-page intent is active.
  void syncScene(SceneType scene) {
    final sceneCategory = switch (scene) {
      SceneType.lake => NearbyPlaceCategory.waterfront,
      SceneType.village => NearbyPlaceCategory.humanity,
      SceneType.unknown ||
      SceneType.city ||
      SceneType.mountain ||
      SceneType.desert ||
      SceneType.driving ||
      SceneType.hiking => NearbyPlaceCategory.viewpoint,
    };
    if (sceneCategory == state.sceneCategory) return;
    state = ExploreIntentState(
      category: state.followsScene && !state.hasActiveIntent
          ? sceneCategory
          : state.category,
      activeFocus: state.activeFocus,
      sceneCategory: sceneCategory,
      followsScene: state.followsScene,
    );
  }

  /// Timeout restores the latest context-derived layer. Returns false when
  /// there was no temporary intent to expire.
  bool expire() {
    if (!state.hasActiveIntent) return false;
    state = ExploreIntentState(
      category: state.sceneCategory,
      sceneCategory: state.sceneCategory,
    );
    return true;
  }
}

final exploreIntentProvider =
    NotifierProvider<ExploreIntentController, ExploreIntentState>(
      ExploreIntentController.new,
    );
