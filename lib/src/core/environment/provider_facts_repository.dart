import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract interface class ProviderFactsRepository {
  Future<ProviderFactsBundle> fetch(
    GeoPoint point, {
    int radiusKm = 25,
    String locale = 'zh-CN',
  });
}
