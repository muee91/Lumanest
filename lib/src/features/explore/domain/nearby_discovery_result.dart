import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class NearbyDiscoveryResult {
  const NearbyDiscoveryResult({
    required this.places,
    required this.entries,
    required this.mode,
    required this.observedAt,
  });

  final List<NearbyPlace> places;
  final List<ContextEntry> entries;
  final String mode;
  final DateTime observedAt;
}
