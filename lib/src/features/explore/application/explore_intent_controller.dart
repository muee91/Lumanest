import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_photo_theme_focus.dart';

class ExploreIntentState {
  const ExploreIntentState({
    required this.category,
    this.activeFocus,
    this.creativeIntent,
    this.regionTheme,
    this.sceneCategory = NearbyPlaceCategory.viewpoint,
    this.followsScene = true,
  });

  final NearbyPlaceCategory category;
  final ExploreFocus? activeFocus;
  final ExploreCreativeIntent? creativeIntent;
  final RegionPhotoTheme? regionTheme;
  final NearbyPlaceCategory sceneCategory;
  final bool followsScene;

  bool get hasActiveIntent => activeFocus != null;
}

class ExploreIntentController extends Notifier<ExploreIntentState> {
  @override
  ExploreIntentState build() =>
      const ExploreIntentState(category: NearbyPlaceCategory.viewpoint);

  /// Activates a focus explicitly requested by a Today/Intelligence action.
  /// A plain Explore route preserves a manual category or regional theme,
  /// unless it is clearing an active temporary focus.
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

  /// Keeps the verified regional label while mapping it to the bounded nearby
  /// query vocabulary. The label is later forwarded to Discovery as search
  /// focus, so a theme such as “潮汐海塘” is not reduced to generic “水岸”.
  void chooseRegionTheme(RegionPhotoTheme theme) {
    state = ExploreIntentState(
      category: focusForRegionPhotoTheme(theme).category,
      regionTheme: theme,
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
      SceneType.city ||
      SceneType.mountain ||
      SceneType.desert ||
      SceneType.unknown => NearbyPlaceCategory.viewpoint,
    };
    if (sceneCategory == state.sceneCategory) return;
    state = ExploreIntentState(
      category: state.followsScene && !state.hasActiveIntent
          ? sceneCategory
          : state.category,
      activeFocus: state.activeFocus,
      creativeIntent: state.creativeIntent,
      regionTheme: state.regionTheme,
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
