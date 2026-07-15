import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class ExploreIntentState {
  const ExploreIntentState({required this.category, this.activeFocus});

  final NearbyPlaceCategory category;
  final ExploreFocus? activeFocus;

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
      state = const ExploreIntentState(category: NearbyPlaceCategory.viewpoint);
      return;
    }
    state = ExploreIntentState(category: focus.category, activeFocus: focus);
  }

  /// A user-picked category or a completed route/search action takes over from
  /// temporary intent without forcing the photography default.
  void complete({required NearbyPlaceCategory category}) {
    state = ExploreIntentState(category: category);
  }

  /// Timeout restores the photography layer. Returns false when there was no
  /// temporary intent to expire.
  bool expire() {
    if (!state.hasActiveIntent) return false;
    state = const ExploreIntentState(category: NearbyPlaceCategory.viewpoint);
    return true;
  }
}

final exploreIntentProvider =
    NotifierProvider<ExploreIntentController, ExploreIntentState>(
      ExploreIntentController.new,
    );
