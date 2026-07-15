import 'package:luma_nest/src/core/location/geo_point.dart';

class WildlifeMapAreaSource {
  const WildlifeMapAreaSource({
    required this.attribution,
    required this.version,
    this.updatedAt,
  });

  final String attribution;
  final String version;
  final DateTime? updatedAt;
}

class WildlifeMapArea {
  WildlifeMapArea({
    required this.id,
    required this.name,
    required List<List<GeoPoint>> polygons,
    required this.source,
  }) : polygons = List.unmodifiable(
         polygons.map((polygon) => List<GeoPoint>.unmodifiable(polygon)),
       );

  final String id;
  final String name;
  final List<List<GeoPoint>> polygons;
  final WildlifeMapAreaSource source;
}

class WildlifeMapLayer {
  WildlifeMapLayer({
    required this.generatedAt,
    required this.radiusKilometers,
    List<WildlifeMapArea> areas = const [],
    this.cachedAt,
  }) : areas = List.unmodifiable(areas);

  final DateTime generatedAt;
  final int radiusKilometers;
  final List<WildlifeMapArea> areas;
  final DateTime? cachedAt;

  bool get isOfflineCache => cachedAt != null;

  List<String> get attributions =>
      List.unmodifiable({for (final area in areas) area.source.attribution});
}
