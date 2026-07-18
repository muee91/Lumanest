import 'package:luma_nest/src/core/location/geo_point.dart';

class PopularPlaceEvidence {
  const PopularPlaceEvidence({
    required this.id,
    required this.title,
    required this.point,
    required this.distanceMeters,
    required this.sourceCount,
    this.address,
  });

  final String id;
  final String title;
  final GeoPoint point;
  final int distanceMeters;
  final int sourceCount;
  final String? address;
}

abstract interface class PopularPlaceEvidenceRepository {
  Future<List<PopularPlaceEvidence>> fetch({
    required GeoPoint center,
    required int radiusMeters,
    required String focus,
  });
}
