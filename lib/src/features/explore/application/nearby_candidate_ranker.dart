import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/popular_place_evidence.dart';

abstract final class NearbyCandidateRanker {
  static List<NearbyPlace> mergeEvidence(
    List<NearbyPlace> places,
    List<PopularPlaceEvidence> evidence,
    NearbyPlaceCategory category,
  ) {
    final remaining = [...evidence];
    final merged = places.map((place) {
      final match = remaining
          .where((item) => _matches(place, item))
          .firstOrNull;
      if (match == null) return place;
      remaining.remove(match);
      return place.copyWith(sourceEvidenceCount: match.sourceCount);
    }).toList();
    for (final item in remaining) {
      merged.add(
        NearbyPlace(
          id: 'discovery:${item.id}',
          name: item.title,
          category: category,
          point: item.point,
          distanceMeters: item.distanceMeters,
          address: item.address,
          matchedKeyword: '来源资料',
          sourceEvidenceCount: item.sourceCount,
          aiDiscovered: true,
        ),
      );
    }
    return List.unmodifiable(merged);
  }

  static List<NearbyPlace> shortlist(
    List<NearbyPlace> places, {
    int maximum = 16,
  }) {
    final ordered = [...places]..sort(_preRouteCompare);
    final selected = <NearbyPlace>[];
    final ids = <String>{};

    void add(NearbyPlace place) {
      if (selected.length < maximum && ids.add(place.id)) selected.add(place);
    }

    for (final place in ordered.where(
      (place) => place.sourceEvidenceCount > 0,
    )) {
      add(place);
    }
    final keywordOrder = places.isEmpty
        ? const <String>[]
        : places.first.category.searchKeywords;
    for (final keyword in keywordOrder) {
      final group = ordered.where((place) => place.matchedKeyword == keyword);
      if (group.isNotEmpty) add(group.first);
    }
    for (final keyword in keywordOrder) {
      final group = ordered
          .where((place) => place.matchedKeyword == keyword)
          .skip(1);
      if (group.isNotEmpty) add(group.first);
    }
    if (selected.length < maximum) {
      for (final place in ordered) {
        add(place);
      }
    }
    return List.unmodifiable(selected);
  }

  static List<NearbyPlace> rank(
    List<NearbyPlace> places, {
    required int radiusMeters,
    int maximum = 16,
  }) {
    final ordered = [...places]
      ..sort((first, second) {
        final score = _score(
          second,
          radiusMeters,
        ).compareTo(_score(first, radiusMeters));
        return score != 0
            ? score
            : first.distanceMeters.compareTo(second.distanceMeters);
      });
    return List.unmodifiable(ordered.take(maximum));
  }

  static double _score(NearbyPlace place, int radiusMeters) {
    final boundedRadius = radiusMeters.clamp(100, 50000);
    final radiusScore =
        (1 - place.distanceMeters / boundedRadius).clamp(0.0, 1.0) * .30;
    final driveSeconds = place.drivingDurationSeconds;
    final driveScore = driveSeconds == null
        ? 0.0
        : (1 - driveSeconds / 7200).clamp(0.0, 1.0) * .40;
    final administrationScore = switch (place.administrativeRelation) {
      NearbyAdministrativeRelation.sameDistrict => .18,
      NearbyAdministrativeRelation.sameCity => .12,
      NearbyAdministrativeRelation.nearbyRegion => .06,
      NearbyAdministrativeRelation.unknown => 0.0,
    };
    // Search-derived evidence is intentionally a bounded supporting signal. It
    // cannot outweigh real travel time, radius or administrative context.
    final sourceScore =
        (place.sourceEvidenceCount.clamp(0, 2) / 2).toDouble() * .12;
    return radiusScore + driveScore + administrationScore + sourceScore;
  }

  static int _preRouteCompare(NearbyPlace first, NearbyPlace second) {
    final evidence = second.sourceEvidenceCount.compareTo(
      first.sourceEvidenceCount,
    );
    if (evidence != 0) return evidence;
    final admin = _adminWeight(second).compareTo(_adminWeight(first));
    if (admin != 0) return admin;
    return first.distanceMeters.compareTo(second.distanceMeters);
  }

  static int _adminWeight(NearbyPlace place) =>
      switch (place.administrativeRelation) {
        NearbyAdministrativeRelation.sameDistrict => 3,
        NearbyAdministrativeRelation.sameCity => 2,
        NearbyAdministrativeRelation.nearbyRegion => 1,
        NearbyAdministrativeRelation.unknown => 0,
      };

  static bool _matches(NearbyPlace place, PopularPlaceEvidence evidence) {
    final placeName = _normalizedName(place.name);
    final evidenceName = _normalizedName(evidence.title);
    if (placeName.length >= 3 &&
        evidenceName.length >= 3 &&
        (placeName.contains(evidenceName) ||
            evidenceName.contains(placeName))) {
      return true;
    }
    final evidencePoint = place.point.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.wgs84ToGcj02(evidence.point)
        : evidence.point;
    return GeoDistance.metersBetween(place.point, evidencePoint) <= 400;
  }

  static String _normalizedName(String value) => value
      .replaceAll(RegExp(r'[\s·()（）\-—_]'), '')
      .replaceAll(RegExp(r'(景区|公园|广场|旅游区)$'), '')
      .toLowerCase();
}
