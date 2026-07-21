import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

class RegionBriefRequest {
  RegionBriefRequest({
    required this.snapshotId,
    required this.activationType,
    required this.locale,
    required this.center,
    required this.radiusMeters,
    required this.sceneProfile,
    required Iterable<String> requestedSections,
  }) : requestedSections = List.unmodifiable(requestedSections);

  final String snapshotId;
  final String activationType;
  final String locale;
  final GeoPoint center;
  final int radiusMeters;
  final ExplorationSceneProfile sceneProfile;
  final List<String> requestedSections;
}

abstract interface class RegionBriefRepository {
  Future<RegionBrief> fetch(RegionBriefRequest request);
}
