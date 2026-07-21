import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/features/explore/domain/explore_composition.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

/// One deterministic decision point for Explore's top-level layout.
///
/// It accepts only already-normalized environment facts and a source-validated
/// brief. It does not rank POIs, generate text, or convert a clue into a
/// photography navigation target.
class ExploreCompositionEngine {
  const ExploreCompositionEngine();

  ExploreComposition compose({
    required ContextSnapshot? snapshot,
    required RegionBrief? brief,
    ContextEntry? blockingSafety,
    required DateTime now,
  }) {
    final hasSafety =
        blockingSafety != null ||
        snapshot?.events.any(
              (event) =>
                  (event.channel == ContextEventChannel.safety ||
                      event.channel == ContextEventChannel.wildlifeSafety) &&
                  !event.isExpiredAt(now.toUtc()),
            ) ==
            true;
    if (hasSafety) {
      return ExploreComposition(
        layoutMode: ExploreLayoutMode.safetyFirst,
        blockingSafety: blockingSafety,
        brief: null,
      );
    }
    if (snapshot?.routeStage == ContextRouteStage.active &&
        snapshot?.routeMode == ContextRouteMode.driving) {
      return ExploreComposition(
        layoutMode: ExploreLayoutMode.routeFirst,
        blockingSafety: null,
        brief: brief?.hasUsableFacts == true ? brief : null,
      );
    }
    if (brief?.hasUsableFacts == true) {
      return ExploreComposition(
        layoutMode: ExploreLayoutMode.briefFirst,
        blockingSafety: null,
        brief: brief,
      );
    }
    return const ExploreComposition(
      layoutMode: ExploreLayoutMode.mapFirst,
      blockingSafety: null,
      brief: null,
    );
  }
}
