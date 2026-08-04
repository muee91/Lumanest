import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_photo_theme_focus.dart';

/// Stable Explore vocabulary. These two controls never move with location,
/// which preserves spatial memory while regional themes remain contextual.
const exploreCoreIntents = <ExploreCreativeIntent>[
  ExploreCreativeIntent.viewpoint,
  ExploreCreativeIntent.humanity,
];

/// Utility POIs remain a separate semantic group, but every item is exposed
/// directly in Explore's single horizontally scrollable tab strip.
const exploreNearbyServiceIntents = <ExploreCreativeIntent>[
  ExploreCreativeIntent.supplies,
  ExploreCreativeIntent.parking,
  ExploreCreativeIntent.food,
  ExploreCreativeIntent.fuel,
  ExploreCreativeIntent.medical,
];

bool isExploreNearbyServiceIntent(ExploreCreativeIntent? intent) =>
    intent != null && exploreNearbyServiceIntents.contains(intent);

NearbyPlaceCategory categoryForExploreRegionTheme(RegionPhotoTheme theme) =>
    focusForRegionPhotoTheme(theme).category;

/// Shows at most two source-validated regional themes. Duplicate identifiers
/// or labels are collapsed deterministically so a noisy brief cannot expand
/// the navigation strip.
List<RegionPhotoTheme> selectExploreRegionThemes(
  Iterable<RegionPhotoTheme> themes, {
  int maxItems = 2,
}) {
  if (maxItems <= 0) return const <RegionPhotoTheme>[];
  final selected = <RegionPhotoTheme>[];
  final ids = <String>{};
  final labels = <String>{};
  for (final theme in themes) {
    final id = theme.id.trim();
    final label = theme.label.trim();
    if (id.isEmpty || label.isEmpty) continue;
    final normalizedLabel = label.toLowerCase();
    if (!ids.add(id) || !labels.add(normalizedLabel)) continue;
    selected.add(RegionPhotoTheme(id: id, label: label));
    if (selected.length == maxItems) break;
  }
  return List.unmodifiable(selected);
}
