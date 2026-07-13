import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

class RouteCorridorScanner {
  const RouteCorridorScanner(this._places);

  final NearbyPlaceRepository _places;

  Future<List<NearbyPlace>> scan(DrivingRoute route) async {
    final samples = _sample(route.polyline, maximum: 4);
    final unique = <String, NearbyPlace>{};
    for (final point in samples) {
      final categories = route.travelMode == RouteTravelMode.walking
          ? const [NearbyPlaceCategory.supply]
          : const [NearbyPlaceCategory.fuel, NearbyPlaceCategory.supply];
      for (final category in categories) {
        final results = await _places.fetchNearby(
          center: point,
          category: category,
          radiusMeters: 5000,
        );
        for (final place in results) {
          unique.putIfAbsent(place.id, () => place);
        }
      }
    }
    final result = unique.values.toList(growable: false);
    result.sort((a, b) {
      final categoryOrder = a.category.index.compareTo(b.category.index);
      return categoryOrder != 0
          ? categoryOrder
          : a.distanceMeters.compareTo(b.distanceMeters);
    });
    return result;
  }

  List<GeoPoint> _sample(List<GeoPoint> points, {required int maximum}) {
    if (points.isEmpty) return const [];
    if (points.length <= maximum) return List.unmodifiable(points);
    return List.generate(maximum, (index) {
      final ratio = index / (maximum - 1);
      return points[(ratio * (points.length - 1)).round()];
    }, growable: false);
  }
}
