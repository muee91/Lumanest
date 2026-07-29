import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

/// Resolves a verified regional theme to the existing, bounded nearby-search
/// vocabulary. This opens candidates around the user; it never upgrades a
/// theme to a reviewed photography target.
ExploreFocus focusForRegionPhotoTheme(RegionPhotoTheme theme) {
  final descriptor = '${theme.id} ${theme.label}';
  if (_matchesAny(descriptor, const [
    'water',
    'lake',
    'river',
    'coast',
    '水',
    '湖',
    '河',
    '江',
    '海',
    '岸',
  ])) {
    return ExploreFocus.water;
  }
  if (_matchesAny(descriptor, const [
    'humanity',
    'street',
    'architecture',
    'heritage',
    'culture',
    'history',
    '街',
    '巷',
    '建筑',
    '人文',
    '文化',
    '历史',
    '民俗',
  ])) {
    return ExploreFocus.humanity;
  }
  return ExploreFocus.photography;
}

bool _matchesAny(String value, List<String> terms) => terms.any(value.contains);
