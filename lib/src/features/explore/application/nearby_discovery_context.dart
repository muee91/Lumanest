import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

enum NearbyDiscoveryMode { passive, explicit, routeCorridor }

class NearbyDiscoveryContext {
  const NearbyDiscoveryContext({
    required this.origin,
    required this.searchCenter,
    required this.radiusMeters,
    required this.intent,
    required this.mode,
    required this.now,
    required this.snapshot,
  });

  final GeoPoint origin;
  final GeoPoint searchCenter;
  final int radiusMeters;
  final NearbyPlaceCategory intent;
  final NearbyDiscoveryMode mode;
  final DateTime now;
  final ContextSnapshot snapshot;
}
