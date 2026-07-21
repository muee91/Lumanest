import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

enum ExploreLayoutMode { briefFirst, routeFirst, mapFirst }

class ExploreComposition {
  const ExploreComposition({required this.layoutMode, required this.brief});

  final ExploreLayoutMode layoutMode;
  final RegionBrief? brief;

  bool get showsBriefFirst => layoutMode == ExploreLayoutMode.briefFirst;
}
