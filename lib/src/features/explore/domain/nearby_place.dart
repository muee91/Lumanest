import 'package:luma_nest/src/core/location/geo_point.dart';

enum NearbyPlaceCategory {
  viewpoint('机位', '观景台'),
  waterfront('湖岸', '湖泊'),
  humanity('人文', '古镇'),
  fuel('加油', '加油站'),
  food('吃饭', '餐饮'),
  supply('补给', '超市'),
  parking('停车', '停车场'),
  medical('医疗', '医院');

  const NearbyPlaceCategory(this.label, this.keyword);

  final String label;
  final String keyword;
}

/// The small, photography-first vocabulary exposed by Explore.
///
/// Each intent resolves to one existing, privacy-preserving nearby query.  It
/// deliberately does not invent a new POI type or turn the map into a
/// navigation directory.
enum ExploreCreativeIntent {
  chaseLight('追光', NearbyPlaceCategory.viewpoint),
  reflection('倒影', NearbyPlaceCategory.waterfront),
  mountain('看山', NearbyPlaceCategory.viewpoint),
  stargazing('星空', NearbyPlaceCategory.viewpoint),
  humanity('人文', NearbyPlaceCategory.humanity),
  supplies('补给', NearbyPlaceCategory.supply),
  shelter('避雨', NearbyPlaceCategory.food);

  const ExploreCreativeIntent(this.label, this.category);

  final String label;
  final NearbyPlaceCategory category;
}

enum ExploreFocus {
  photography('附近摄影线索'),
  water('正在寻找湖岸与水面线索'),
  humanity('正在寻找街巷与人文线索'),
  wildlife('正在查看区域野生动物线索');

  const ExploreFocus(this.label);
  final String label;

  static ExploreFocus fromQuery(String? value) => switch (value) {
    'water' => ExploreFocus.water,
    'humanity' => ExploreFocus.humanity,
    'wildlife' => ExploreFocus.wildlife,
    _ => ExploreFocus.photography,
  };

  NearbyPlaceCategory get category => switch (this) {
    ExploreFocus.water => NearbyPlaceCategory.waterfront,
    ExploreFocus.humanity => NearbyPlaceCategory.humanity,
    ExploreFocus.photography ||
    ExploreFocus.wildlife => NearbyPlaceCategory.viewpoint,
  };
}

class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.point,
    required this.distanceMeters,
    this.address,
    this.cachedAt,
  });

  final String id;
  final String name;
  final NearbyPlaceCategory category;
  final GeoPoint point;
  final int distanceMeters;
  final String? address;
  final DateTime? cachedAt;

  bool get isOfflineCache => cachedAt != null;
}
