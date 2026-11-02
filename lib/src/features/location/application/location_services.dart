import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

/// Place-name lookup for presentation surfaces.
///
/// Pages decide *when* a query is issued and what to render; this layer owns
/// which repository is used and, for the map surface, which centre the ranking
/// is biased toward. Presentation never reaches into the repository directly.
class LocationSearchService {
  LocationSearchService(this._ref);

  final Ref _ref;

  /// Global place search, used where the caller has no environment fix yet.
  Future<List<LocationSearchResult>> search(String query) =>
      _ref.read(locationSearchRepositoryProvider).search(query);

  /// Search biased toward the area the environment snapshot describes. The
  /// snapshot future is awaited so a query typed before the first fix still
  /// resolves against the right region instead of silently going global.
  Future<List<LocationSearchResult>> searchAroundEnvironment(String query) async {
    final snapshot = await _ref.read(environmentSnapshotProvider.future);
    return _ref
        .read(locationSearchRepositoryProvider)
        .search(query, center: snapshot.location);
  }
}

final locationSearchServiceProvider = Provider<LocationSearchService>(
  LocationSearchService.new,
);

/// Foreground device fix used by Field Mode arrival checks.
///
/// Manual and base-region selections are valid for environment lookup, but
/// they must never auto-confirm physical arrival at a reviewed target, so this
/// deliberately bypasses `effectiveLocationRepositoryProvider`.
class DeviceLocationFixService {
  DeviceLocationFixService(this._ref);

  final Ref _ref;

  Future<LocationReading> current() =>
      _ref.read(locationRepositoryProvider).current();
}

final deviceLocationFixServiceProvider = Provider<DeviceLocationFixService>(
  DeviceLocationFixService.new,
);
