import 'package:luma_nest/src/core/location/geo_point.dart';

class ElevationProfile {
  ElevationProfile({required this.source, required List<double> elevations})
    : elevations = List.unmodifiable(elevations);

  final String source;
  final List<double> elevations;
}

abstract interface class ElevationProfileRepository {
  Future<ElevationProfile> fetch(List<GeoPoint> points);
}
