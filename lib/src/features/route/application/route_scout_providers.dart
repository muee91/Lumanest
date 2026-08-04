import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_scout_plan.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';

class RouteScoutRequest {
  const RouteScoutRequest({
    required this.route,
    required this.destination,
    required this.routeKey,
  });

  final DrivingRoute route;
  final RouteDestination destination;
  final String routeKey;

  @override
  bool operator ==(Object other) =>
      other is RouteScoutRequest &&
      other.routeKey == routeKey &&
      other.route.durationSeconds == route.durationSeconds &&
      other.route.distanceMeters == route.distanceMeters &&
      other.route.polyline.length == route.polyline.length;

  @override
  int get hashCode => Object.hash(
    routeKey,
    route.durationSeconds,
    route.distanceMeters,
    route.polyline.length,
  );
}

final routeScoutPlanProvider = FutureProvider.autoDispose
    .family<RouteScoutPlan, RouteScoutRequest>((ref, request) async {
      final now = ref.watch(currentTimeProvider)();
      final snapshot = await ref.watch(environmentSnapshotProvider.future);
      final corridor = RouteCorridorContext.fromPolyline(
        polyline: request.route.polyline,
        durationSeconds: request.route.durationSeconds,
        departureAt: now,
        routeSeed: request.routeKey,
        maximumSamples: 5,
      );
      final weatherFuture = _optionalWeather(
        ref.watch(routeWeatherRepositoryProvider),
        corridor,
      );
      final supportFuture = _loadSupportStops(ref, request.route, corridor);
      final (weather, supportStops) = await (weatherFuture, supportFuture).wait;
      return RouteScoutPlanBuilder.build(
        routeId: corridor.routeId,
        route: request.route,
        snapshot: snapshot,
        now: now,
        weather: weather,
        supportStops: supportStops,
      );
    });

Future<RouteWeatherReport?> _optionalWeather(
  RouteWeatherRepository repository,
  RouteCorridorContext corridor,
) async {
  try {
    return await repository.fetch(corridor);
  } on Object {
    return null;
  }
}

Future<List<RouteSupportStop>> _loadSupportStops(
  Ref ref,
  DrivingRoute route,
  RouteCorridorContext corridor,
) async {
  final cache = ref.watch(routeSupportCacheProvider);
  final cached = await cache.readMatching(route) ?? const <RouteSupportStop>[];
  final queries = _supportQueries(route, corridor);
  if (queries.isEmpty) return cached;

  final repository = ref.watch(nearbyPlaceRepositoryProvider);
  final fresh = <RouteSupportStop>[];
  for (var index = 0; index < queries.length; index += 2) {
    final batch = queries.skip(index).take(2);
    final results = await Future.wait(
      batch.map((query) => _findSupportStop(repository, query)),
    );
    fresh.addAll(results.whereType<RouteSupportStop>());
  }
  if (fresh.isEmpty) return cached;

  final seen = <String>{};
  final merged = <RouteSupportStop>[
    ...fresh.where((stop) => seen.add(stop.place.id)),
    ...cached.where((stop) => seen.add(stop.place.id)),
  ];
  // Only replace a populated route cache after every requested service type
  // produced a fresh candidate. A partial network response may enrich the
  // current view, but it must not erase a still-valid fuel or medical fallback.
  if (fresh.length == queries.length || cached.isEmpty) {
    await cache.write(route, fresh);
  }
  return List.unmodifiable(merged.take(12));
}

Future<RouteSupportStop?> _findSupportStop(
  NearbyPlaceRepository repository,
  _SupportQuery query,
) async {
  final places = await fetchOptionalNearbyPlaces(
    repository,
    center: query.sample.point,
    category: query.category,
    radiusMeters: query.radiusMeters,
  );
  final place = places
      .where((candidate) => candidate.category == query.category)
      .firstOrNull;
  return place == null
      ? null
      : RouteSupportStop(
          place: place,
          routeProgress: query.sample.progress,
        );
}

List<_SupportQuery> _supportQueries(
  DrivingRoute route,
  RouteCorridorContext corridor,
) {
  if (corridor.samples.length < 2) return const [];
  final samples = corridor.samples;
  final middle = samples[samples.length ~/ 2];
  final late = samples.length >= 4 ? samples[samples.length - 2] : middle;
  final destination = samples.last;
  final queries = <_SupportQuery>[];
  final durationMinutes = (route.durationSeconds / 60).ceil();
  final driving = route.travelMode == RouteTravelMode.driving;

  if (driving && route.distanceMeters >= 50000) {
    queries.add(
      _SupportQuery(
        sample: middle,
        category: NearbyPlaceCategory.fuel,
        radiusMeters: 6000,
      ),
    );
  }
  if (durationMinutes >= (driving ? 90 : 60)) {
    queries.add(
      _SupportQuery(
        sample: middle,
        category: NearbyPlaceCategory.supply,
        radiusMeters: 5000,
      ),
    );
  }
  if (durationMinutes >= 120) {
    queries.add(
      _SupportQuery(
        sample: late,
        category: NearbyPlaceCategory.food,
        radiusMeters: 5000,
      ),
    );
  }
  if (driving) {
    queries.add(
      _SupportQuery(
        sample: destination,
        category: NearbyPlaceCategory.parking,
        radiusMeters: 4000,
      ),
    );
  }
  if (route.distanceMeters >= 120000 || durationMinutes >= 180) {
    queries.add(
      _SupportQuery(
        sample: late,
        category: NearbyPlaceCategory.medical,
        radiusMeters: 8000,
      ),
    );
  }
  return List.unmodifiable(queries.take(4));
}

class _SupportQuery {
  const _SupportQuery({
    required this.sample,
    required this.category,
    required this.radiusMeters,
  });

  final RouteCorridorSample sample;
  final NearbyPlaceCategory category;
  final int radiusMeters;
}
