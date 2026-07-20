import 'package:luma_nest/src/core/entry/entry_adapter.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_context.dart';
import 'package:luma_nest/src/features/explore/application/nearby_discovery_policy.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_discovery_result.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';

class NearbyDiscoveryEngine {
  const NearbyDiscoveryEngine();

  NearbyDiscoveryResult rank(
    Iterable<NearbyPlace> candidates,
    NearbyDiscoveryContext context,
  ) {
    final filtered = NearbyDiscoveryPolicy.hardFilter(candidates, context);
    final ranked = filtered.toList(growable: false)
      ..sort((left, right) {
        final score = NearbyDiscoveryPolicy.score(
          right,
          context,
        ).compareTo(NearbyDiscoveryPolicy.score(left, context));
        if (score != 0) return score;
        return left.distanceMeters.compareTo(right.distanceMeters);
      });
    final threshold = NearbyDiscoveryPolicy.threshold(context.mode);
    final places = ranked
        .where(
          (place) => NearbyDiscoveryPolicy.score(place, context) >= threshold,
        )
        .take(NearbyDiscoveryPolicy.limit(context.mode))
        .toList(growable: false);
    return NearbyDiscoveryResult(
      places: places,
      entries: places
          .map(
            (place) => ContextEntryAdapter.fromNearbyPlace(
              place,
              observedAt: context.now,
            ),
          )
          .toList(growable: false),
      mode: context.mode.name,
      observedAt: context.now,
    );
  }
}
