import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

enum ExploreLayoutMode { briefFirst, routeFirst, safetyFirst, mapFirst }

class ExploreComposition {
  const ExploreComposition({
    required this.layoutMode,
    required this.blockingSafety,
    required this.brief,
  });

  final ExploreLayoutMode layoutMode;
  final ContextEntry? blockingSafety;
  final RegionBrief? brief;

  bool get showsBriefFirst => layoutMode == ExploreLayoutMode.briefFirst;
}
