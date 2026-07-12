import 'package:luma_nest/src/core/location/geo_point.dart';

enum NearbyPlaceCategory {
  viewpoint('机位', '观景台'),
  fuel('加油', '加油站'),
  food('吃饭', '餐饮'),
  supply('补给', '超市'),
  parking('停车', '停车场'),
  medical('医疗', '医院');

  const NearbyPlaceCategory(this.label, this.keyword);

  final String label;
  final String keyword;
}

class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.point,
    required this.distanceMeters,
    this.address,
  });

  final String id;
  final String name;
  final NearbyPlaceCategory category;
  final GeoPoint point;
  final int distanceMeters;
  final String? address;
}
