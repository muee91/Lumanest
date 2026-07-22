import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract interface class SiteEnvironmentRepository {
  Future<SiteEnvironmentFacts> fetch(GeoPoint point);
}
