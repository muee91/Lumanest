import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/application/amap_navigation_handoff.dart';
import 'package:luma_nest/src/features/route/application/gpx_track_import_service.dart';
import 'package:luma_nest/src/features/route/application/route_corridor_scanner.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:luma_nest/src/features/route/domain/route_timeline.dart';
import 'package:luma_nest/src/features/route/domain/hiking_return_assessment.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/route/infrastructure/gpx_track_parser.dart';
import 'package:luma_nest/src/features/route/presentation/route_map_preview.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/notifications/application/route_reminder_service.dart';
import 'package:luma_nest/src/shared/widgets/responsive_action_group.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_surface.dart';

class RoutePage extends ConsumerWidget {
  const RoutePage({
    super.key,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
    this.importedTrackId,
    this.routeAsync,
    this.contextSnapshot,
    this.timelineNow,
    this.routeMapBuilder,
    this.travelMode = RouteTravelMode.driving,
  });

  final String? destinationName;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String? importedTrackId;
  final AsyncValue<DrivingRoute>? routeAsync;
  final ContextSnapshot? contextSnapshot;
  final DateTime? timelineNow;
  final RouteMapBuilder? routeMapBuilder;
  final RouteTravelMode travelMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (importedTrackId case final trackId? when trackId.isNotEmpty) {
      return ref
          .watch(userLibraryProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const _ImportedTrackUnavailableView(),
            data: (library) {
              final track = library.importedTrack(trackId);
              if (track == null) return const _ImportedTrackUnavailableView();
              return _buildImportedTrack(ref, track);
            },
          );
    }
    if (destinationName == null ||
        destinationLatitude == null ||
        destinationLongitude == null) {
      return ref
          .watch(userLibraryProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const _RouteNoneSync(child: _EmptyRouteView()),
            data: (library) {
              final active = library.activeJourney;
              if (active == null) {
                return const _RouteNoneSync(child: _EmptyRouteView());
              }
              final routeKey = active.routeKey;
              if (routeKey != null && routeKey.isNotEmpty) {
                final track = library.importedTrack(routeKey);
                if (track == null) {
                  return _ActiveTrackUnavailableView(active);
                }
                return _buildImportedTrack(ref, track);
              }
              final mode = active.destination.travelMode == 'walking'
                  ? RouteTravelMode.walking
                  : RouteTravelMode.driving;
              return _buildRoute(context, ref, active.destination, mode: mode);
            },
          );
    }
    return _buildRoute(
      context,
      ref,
      SavedRouteDestination(
        name: destinationName!,
        latitude: destinationLatitude!,
        longitude: destinationLongitude!,
        travelMode: travelMode.name,
      ),
      mode: travelMode,
    );
  }

  Widget _buildImportedTrack(WidgetRef ref, ImportedRouteTrack track) {
    final snapshot =
        contextSnapshot ?? ref.watch(environmentSnapshotProvider).asData?.value;
    final destination = track.destination;
    return SafeArea(
      child: _RouteContent(
        route: track.toRoute(),
        snapshot: snapshot,
        departureAt: timelineNow ?? DateTime.now(),
        routeMapBuilder: routeMapBuilder,
        travelMode: RouteTravelMode.walking,
        destinationLatitude: destination.latitude,
        destinationLongitude: destination.longitude,
        destinationCoordinateSystem: destination.coordinateSystem,
      ),
    );
  }

  Widget _buildRoute(
    BuildContext context,
    WidgetRef ref,
    SavedRouteDestination saved, {
    required RouteTravelMode mode,
  }) {
    final destination = RouteDestination(
      name: saved.name,
      point: GeoPoint(
        latitude: saved.latitude,
        longitude: saved.longitude,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
      travelMode: mode,
    );
    final AsyncValue<DrivingRoute> route =
        routeAsync ?? ref.watch(drivingRouteProvider(destination));
    final snapshot =
        contextSnapshot ??
        (routeAsync == null
            ? ref.watch(environmentSnapshotProvider).asData?.value
            : null);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _RouteModeSelector(
              selected: mode,
              onChanged: (selectedMode) {
                // Do not write route state here: the new route has not loaded
                // yet. Navigating rebuilds RoutePage with the new mode; once the
                // new DrivingRoute succeeds, _RouteContent marks it planned.
                unawaited(
                  ref
                      .read(userLibraryProvider.notifier)
                      .saveRecentRoute(
                        SavedRouteDestination(
                          name: saved.name,
                          latitude: saved.latitude,
                          longitude: saved.longitude,
                          travelMode: selectedMode.name,
                        ),
                      ),
                );
                context.go(
                  Uri(
                    path: '/route',
                    queryParameters: {
                      'name': saved.name,
                      'lat': '${saved.latitude}',
                      'lon': '${saved.longitude}',
                      'mode': selectedMode.name,
                    },
                  ).toString(),
                );
              },
            ),
          ),
          Expanded(
            child: route.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _RouteErrorView(
                onRetry: () =>
                    ref.invalidate(drivingRouteProvider(destination)),
              ),
              data: (value) => _RouteContent(
                route: value,
                snapshot: snapshot,
                departureAt: timelineNow ?? DateTime.now(),
                routeMapBuilder: routeMapBuilder,
                travelMode: mode,
                destinationLatitude: saved.latitude,
                destinationLongitude: saved.longitude,
                destinationCoordinateSystem: CoordinateSystem.gcj02,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteModeSelector extends StatelessWidget {
  const _RouteModeSelector({required this.selected, required this.onChanged});

  final RouteTravelMode selected;
  final ValueChanged<RouteTravelMode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<RouteTravelMode>(
    segments: const [
      ButtonSegment(
        value: RouteTravelMode.driving,
        icon: Icon(Icons.directions_car_outlined),
        label: Text('自驾'),
      ),
      ButtonSegment(
        value: RouteTravelMode.walking,
        icon: Icon(Icons.hiking_outlined),
        label: Text('徒步'),
      ),
    ],
    selected: {selected},
    onSelectionChanged: (selection) => onChanged(selection.single),
    showSelectedIcon: false,
  );
}

class _EmptyRouteView extends ConsumerStatefulWidget {
  const _EmptyRouteView();

  @override
  ConsumerState<_EmptyRouteView> createState() => _EmptyRouteViewState();
}

class _EmptyRouteViewState extends ConsumerState<_EmptyRouteView> {
  bool _importing = false;

  Future<void> _importTrack() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final track = await ref
          .read(gpxTrackImportServiceProvider)
          .pickAndParse();
      if (track == null || !mounted) return;
      await ref.read(userLibraryProvider.notifier).saveImportedTrack(track);
      if (!mounted) return;
      context.go(
        Uri(path: '/route', queryParameters: {'track': track.id}).toString(),
      );
    } on GpxTrackFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_trackFailureMessage(error.kind))));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('轨迹未能保存，请重试')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    final recentRoute = library?.recentRoute;
    final savedRoutes = library?.savedRoutes ?? const [];
    final journeys = library?.journeys ?? const [];
    final importedTracks = library?.importedTracks ?? const [];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          LumaNestSpacing.md,
          LumaNestSpacing.md,
          LumaNestSpacing.md,
          LumaNestSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LumaNestEyebrow(label: '路线规划'),
            const SizedBox(height: LumaNestSpacing.lg),
            LumaNestSurface(
              tone: LumaNestSurfaceTone.paper,
              padding: const EdgeInsets.all(LumaNestSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    size: 30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: LumaNestSpacing.lg),
                  Text(
                    '下一段路，从一个目的地开始',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: LumaNestSpacing.xs),
                  Text(
                    '从探索页选择目的地生成路线，也可以导入已有 GPX 轨迹离线查看。',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LumaNestSpacing.md),
            ResponsiveActionGroup(
              actions: [
                FilledButton.icon(
                  onPressed: () => context.go('/explore'),
                  icon: const Icon(Icons.add_road_outlined),
                  label: const Text('去探索选目的地'),
                ),
                OutlinedButton.icon(
                  onPressed: _importing ? null : _importTrack,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(_importing ? '正在导入' : '导入轨迹'),
                ),
              ],
            ),
            const SizedBox(height: LumaNestSpacing.lg),
            if (savedRoutes.isNotEmpty) ...[
              Text('已保存路线', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final route in savedRoutes)
                ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(route.destination.name),
                  subtitle: Text(
                    route.destination.travelMode == 'walking' ? '徒步' : '自驾',
                  ),
                  trailing: IconButton(
                    tooltip: '删除已保存路线',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref
                        .read(userLibraryProvider.notifier)
                        .deleteSavedRoute(route.id),
                  ),
                  onTap: () =>
                      context.go(_routeUri(route.destination).toString()),
                ),
              const SizedBox(height: 12),
            ],
            if (recentRoute != null)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(recentRoute.name),
                subtitle: const Text('最近规划'),
                trailing: const Icon(Icons.arrow_outward),
                onTap: () => context.go(_routeUri(recentRoute).toString()),
              ),
            if (journeys.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('行程记录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final journey in journeys)
                ListTile(
                  leading: Icon(
                    journey.isActive
                        ? Icons.play_circle_outline
                        : Icons.check_circle_outline,
                  ),
                  title: Text(journey.destination.name),
                  subtitle: Text(
                    journey.isActive
                        ? '进行中 · 仅保存在本机'
                        : '${journey.destination.travelMode == 'walking' ? '徒步' : '自驾'} · ${_dateTime(journey.startedAt)}',
                  ),
                  trailing: IconButton(
                    tooltip: '删除行程记录',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteJourney(journey),
                  ),
                  onTap: () => context.go(_journeyUri(journey).toString()),
                ),
            ],
            for (final track in importedTracks)
              ListTile(
                leading: const Icon(Icons.hiking_outlined),
                title: Text(track.name),
                subtitle: Text(
                  'GPX · ${_distanceLabel(track.distanceMeters)} · 本地保存',
                ),
                trailing: IconButton(
                  tooltip: '删除轨迹',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(userLibraryProvider.notifier)
                      .deleteImportedTrack(track.id),
                ),
                onTap: () => context.go(
                  Uri(
                    path: '/route',
                    queryParameters: {'track': track.id},
                  ).toString(),
                ),
              ),
            if (recentRoute == null &&
                savedRoutes.isEmpty &&
                journeys.isEmpty &&
                importedTracks.isEmpty)
              Text(
                '还没有保存路线或导入轨迹',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Uri _routeUri(SavedRouteDestination destination) => Uri(
    path: '/route',
    queryParameters: {
      'name': destination.name,
      'lat': '${destination.latitude}',
      'lon': '${destination.longitude}',
      'mode': destination.travelMode,
    },
  );

  static Uri _journeyUri(SavedJourney journey) => journey.routeKey == null
      ? _routeUri(journey.destination)
      : Uri(path: '/route', queryParameters: {'track': journey.routeKey});

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _deleteJourney(SavedJourney journey) async {
    if (journey.isActive) {
      try {
        await ref.read(routeReminderServiceProvider).cancel(journey.id);
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('系统返程提醒未能取消，行程记录仍保留')));
        return;
      }
    }
    await ref.read(userLibraryProvider.notifier).deleteJourney(journey.id);
  }

  static String _distanceLabel(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  static String _trackFailureMessage(GpxTrackFailureKind kind) =>
      switch (kind) {
        GpxTrackFailureKind.tooLarge => 'GPX 文件不能超过 5 MB',
        GpxTrackFailureKind.tooManyPoints => '轨迹点过多，请先精简到 20000 点以内',
        GpxTrackFailureKind.noTrackPoints => '没有找到可用的 GPX 轨迹点',
        GpxTrackFailureKind.invalidDocument => '这不是有效的 GPX 轨迹文件',
        GpxTrackFailureKind.unreadable => '无法读取这个文件，请重新选择',
      };
}

class _RouteContent extends ConsumerStatefulWidget {
  const _RouteContent({
    required this.route,
    required this.snapshot,
    required this.departureAt,
    required this.routeMapBuilder,
    required this.travelMode,
    required this.destinationLatitude,
    required this.destinationLongitude,
    required this.destinationCoordinateSystem,
  });

  final DrivingRoute route;
  final ContextSnapshot? snapshot;
  final DateTime departureAt;
  final RouteMapBuilder? routeMapBuilder;
  final RouteTravelMode travelMode;
  final double destinationLatitude;
  final double destinationLongitude;
  final CoordinateSystem destinationCoordinateSystem;

  @override
  ConsumerState<_RouteContent> createState() => _RouteContentState();
}

class _RouteContentState extends ConsumerState<_RouteContent> {
  AsyncValue<List<RouteSupportStop>>? _support;

  @override
  void initState() {
    super.initState();
    _syncPlanned();
    _scheduleAutomaticSupportScan();
  }

  @override
  void didUpdateWidget(covariant _RouteContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.travelMode != widget.travelMode ||
        oldWidget.destinationLatitude != widget.destinationLatitude ||
        oldWidget.destinationLongitude != widget.destinationLongitude ||
        oldWidget.route.sourceId != widget.route.sourceId) {
      _support = null;
      _syncPlanned();
      _scheduleAutomaticSupportScan();
    }
  }

  void _scheduleAutomaticSupportScan() {
    if (widget.route.polyline.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _support != null) return;
      unawaited(_scanSupport());
    });
  }

  /// Marks the route as planned (with the current travel mode) once a route is
  /// successfully displayed. Runs after the current build so it never writes
  /// provider state during build. It only downgrades to planned when the user
  /// is not already active/paused on the same route (identified by destination
  /// coordinates + travel mode), so a rebuild does not reset an in-progress
  /// follow, while switching to a different destination resets to planned.
  void _syncPlanned() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(routeContextStateProvider.notifier);
      final mode = _contextMode(widget.travelMode);
      notifier.plan(
        mode,
        identity: RouteIdentity(
          latitude: widget.destinationLatitude,
          longitude: widget.destinationLongitude,
          mode: mode,
          routeKey: widget.route.sourceId,
        ),
      );
      try {
        final seed = StringBuffer(widget.route.sourceId ?? '')
          ..write(widget.destinationLatitude)
          ..write(',')
          ..write(widget.destinationLongitude)
          ..write(',')
          ..write(widget.travelMode.name);
        ref
            .read(routeCorridorContextProvider.notifier)
            .replace(
              RouteCorridorContext.fromPolyline(
                polyline: widget.route.polyline,
                durationSeconds: widget.route.durationSeconds,
                departureAt: widget.departureAt,
                routeSeed: seed.toString(),
              ),
            );
      } on Object {
        ref.read(routeCorridorContextProvider.notifier).clear();
      }
      try {
        final library = await ref.read(userLibraryProvider.future);
        if (!mounted) return;
        final active = library.activeJourney;
        if (active != null &&
            active.matches(_journeyDestination, routeKey: _journeyRouteKey)) {
          notifier.start();
        }
      } on Object {
        // Route planning remains usable if the optional local library fails.
      }
    });
  }

  SavedRouteDestination get _journeyDestination => SavedRouteDestination(
    name: widget.route.destinationName,
    latitude: widget.destinationLatitude,
    longitude: widget.destinationLongitude,
    travelMode: widget.travelMode.name,
  );

  String? get _journeyRouteKey => widget.route.source == RouteSource.importedGpx
      ? widget.route.sourceId
      : null;

  Future<void> _scanSupport() async {
    setState(() => _support = const AsyncLoading());
    final scanner = RouteCorridorScanner(
      ref.read(nearbyPlaceRepositoryProvider),
      cache: ref.read(routeSupportCacheProvider),
    );
    final result = await AsyncValue.guard(() => scanner.scan(widget.route));
    if (mounted) setState(() => _support = result);
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final snapshot = widget.snapshot;
    final manifest = snapshot == null
        ? null
        : ManifestPolicy.build(snapshot, now: widget.departureAt);
    final safety = manifest?.safety ?? const <ManifestItem>[];
    final hikingAssessment = snapshot == null
        ? null
        : HikingReturnAssessment.build(
            route: route,
            snapshot: snapshot,
            departureAt: widget.departureAt,
          );
    final routeRiskIds = snapshot?.events
        .where(
          (event) =>
              event.geoScope == ContextGeoScope.route &&
              (event.channel == ContextEventChannel.safety ||
                  event.channel == ContextEventChannel.wildlifeSafety) &&
              !event.isExpiredAt(widget.departureAt),
        )
        .map((event) => event.id)
        .toSet();
    final timeline = RouteTimeline.build(
      route: route,
      snapshot: snapshot,
      departureAt: widget.departureAt,
      supportStops: _support?.asData?.value ?? const [],
      routeRisks: routeRiskIds == null
          ? const []
          : safety
                .where((item) => routeRiskIds.contains(item.id))
                .map(
                  (item) => RouteTimelineRisk(id: item.id, title: item.title),
                )
                .toList(growable: false),
      hikingAssessment: hikingAssessment,
    );
    final routeOpportunities = RouteTimeline.eligiblePhotographyOpportunities(
      snapshot,
      departureAt: widget.departureAt,
    );
    final distance = route.distanceMeters >= 1000
        ? '${(route.distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${route.distanceMeters} m';
    final duration = Duration(seconds: route.durationSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationLabel = hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
    final routeState = ref.watch(routeContextStateProvider);
    final destination = SavedRouteDestination(
      name: route.destinationName,
      latitude: widget.destinationLatitude,
      longitude: widget.destinationLongitude,
      travelMode: widget.travelMode.name,
    );
    final routeSaved =
        ref
            .watch(userLibraryProvider)
            .asData
            ?.value
            .containsSavedRoute(destination) ??
        false;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LumaNestSpacing.md,
        LumaNestSpacing.md,
        LumaNestSpacing.md,
        LumaNestSpacing.xl,
      ),
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: LumaNestSpacing.sm),
            Text('路线', style: theme.textTheme.labelLarge),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                route.travelMode == RouteTravelMode.walking ? '徒步计划' : '自驾计划',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: LumaNestSpacing.sm),
        Text(
          route.source == RouteSource.importedGpx
              ? route.destinationName
              : '前往 ${route.destinationName}',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: LumaNestSpacing.md),
        _RouteLifecycleBar(
          state: routeState,
          destination: _journeyDestination,
          routeKey: _journeyRouteKey,
          returnReminderAt: hikingAssessment?.latestReturnDeparture,
        ),
        if (route.source != RouteSource.importedGpx) ...[
          const SizedBox(height: LumaNestSpacing.sm),
          ResponsiveActionGroup(
            actions: [
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(userLibraryProvider.notifier)
                    .toggleSavedRoute(destination),
                icon: Icon(
                  routeSaved ? Icons.bookmark : Icons.bookmark_outline,
                ),
                label: Text(routeSaved ? '取消保存路线' : '保存路线'),
              ),
              if (!route.isStale) ...[
                FilledButton.icon(
                  onPressed: _openAmapNavigation,
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('交给高德导航'),
                ),
              ],
            ],
          ),
        ],
        if (snapshot != null && routeOpportunities.isNotEmpty) ...[
          const SizedBox(height: LumaNestSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _saveOfflinePhotographyPack(
              snapshot: snapshot,
              opportunities: routeOpportunities,
            ),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('保存本次摄影离线包'),
          ),
        ],
        if (route.source == RouteSource.importedGpx) ...[
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: const ListTile(
              leading: Icon(Icons.file_present_outlined),
              title: Text('本地导入轨迹'),
              subtitle: Text('轨迹线来自所选 GPX 文件，可离线查看；不包含实时路况，也不能用于逐向导航。'),
            ),
          ),
        ],
        if (route.isStale) ...[
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: const ListTile(
              leading: Icon(Icons.offline_bolt_outlined),
              title: Text('正在显示离线路线'),
              subtitle: Text('道路、耗时和费用可能已经变化，请勿将缓存结果用于逐向导航。'),
            ),
          ),
        ],
        if (safety.isNotEmpty) ...[
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                for (final item in safety)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(item.title),
                    subtitle: const Text('这是当前环境风险，不代表整段路线的未来状况。'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('路线概览', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        RouteMapPreview(route: route, mapBuilder: widget.routeMapBuilder),
        const SizedBox(height: 20),
        LumaNestSurface(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: _RouteMetric(label: '距离', value: distance),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _RouteMetric(
                  label: route.source == RouteSource.importedGpx
                      ? route.durationEstimated
                            ? '估算用时'
                            : '记录用时'
                      : '预计',
                  value: durationLabel,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _RouteMetric(
                  label: route.travelMode == RouteTravelMode.walking
                      ? '累计爬升'
                      : '过路费',
                  value: route.travelMode == RouteTravelMode.walking
                      ? route.ascentMeters == null
                            ? '暂无高程'
                            : '${route.ascentMeters} m'
                      : route.tollsYuan > 0
                      ? '¥${route.tollsYuan.toStringAsFixed(0)}'
                      : '无',
                ),
              ),
            ],
          ),
        ),
        if (route.elevationSource case final source?) ...[
          const SizedBox(height: 6),
          Text(
            route.source == RouteSource.importedGpx
                ? '高程来源：$source · 可能受设备漂移影响，不替代专业测绘'
                : '高程来源：$source · 采样估算，不替代专业测绘',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (hikingAssessment != null) ...[
          const SizedBox(height: 14),
          _HikingReturnCard(assessment: hikingAssessment),
        ],
        if (timeline.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('行动时间轴', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('补给按路线进度估算；摄影机会仅采用已成立的区域或路线窗口，未推断沿途未来天气和地形遮挡。'),
          const SizedBox(height: 10),
          LumaNestSurface(
            tone: LumaNestSurfaceTone.solid,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final entry in timeline)
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_timelineIcon(entry.kind), size: 18),
                    ),
                    title: Text(entry.label),
                    subtitle: Text(entry.description),
                    trailing: Text(
                      _timelineTime(entry),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text('路线步骤', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Material(
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .82),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: route.instructions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(LumaNestSpacing.md),
                    child: Text(
                      route.source == RouteSource.importedGpx
                          ? 'GPX 仅包含轨迹线，不含道路转向说明。'
                          : '路线已生成，暂时没有详细道路说明。',
                    ),
                  )
                : Column(
                    children: [
                      for (
                        var index = 0;
                        index < route.instructions.length && index < 8;
                        index++
                      )
                        ListTile(
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(route.instructions[index]),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          onPressed: _support?.isLoading == true ? null : _scanSupport,
          icon: Icon(
            route.travelMode == RouteTravelMode.walking
                ? Icons.water_drop_outlined
                : Icons.local_gas_station_outlined,
          ),
          label: Text(
            _support == null
                ? route.travelMode == RouteTravelMode.walking
                      ? '扫描沿途餐饮和补给'
                      : '扫描沿途加油、餐饮和补给'
                : '重新扫描沿途服务点',
          ),
        ),
        if (_support case final support?) ...[
          const SizedBox(height: 14),
          support.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('沿途服务点数据暂时不可用'),
            data: (stops) => _SupportResults(stops: stops),
          ),
        ],
      ],
    );
  }

  Future<void> _openAmapNavigation() async {
    final opened = await ref
        .read(amapNavigationHandoffProvider)
        .open(
          destinationName: widget.route.destinationName,
          destination: GeoPoint(
            latitude: widget.destinationLatitude,
            longitude: widget.destinationLongitude,
            coordinateSystem: widget.destinationCoordinateSystem,
          ),
          mode: widget.travelMode,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(opened ? '已交给高德导航' : '无法打开高德导航，请确认已安装或稍后重试')),
    );
  }

  Future<void> _saveOfflinePhotographyPack({
    required ContextSnapshot snapshot,
    required List<PhotographyOpportunity> opportunities,
  }) async {
    final now = DateTime.now().toUtc();
    final observedAt = snapshot.observedAt.toUtc();
    final pack = OfflinePhotographyPack.create(
      name: '${widget.route.destinationName} 摄影离线包',
      createdAt: now,
      dataTimestamp: observedAt.isAfter(now) ? now : observedAt,
      route: _journeyDestination,
      places: (_support?.asData?.value ?? const <RouteSupportStop>[])
          .map(
            (stop) => SavedPlace(
              id: stop.place.id,
              name: stop.place.name,
              category: stop.place.category.name,
              latitude: stop.place.point.latitude,
              longitude: stop.place.point.longitude,
            ),
          )
          .toList(growable: false),
      windows: opportunities
          .map(
            (opportunity) => OfflinePhotographyWindow(
              id: opportunity.id,
              label: opportunity.title,
              startsAt: opportunity.startsAt,
              endsAt: opportunity.expiresAt,
              peakAt: opportunity.peaksAt,
            ),
          )
          .toList(growable: false),
      opportunitySnapshot: {
        'format': 'lumanest-route-photography-v1',
        'snapshotId': snapshot.id,
        'observedAt': observedAt.toIso8601String(),
        'expiresAt': snapshot.expiresAt.toUtc().toIso8601String(),
        'routeDurationSeconds': widget.route.durationSeconds,
        'supportStops': (_support?.asData?.value ?? const <RouteSupportStop>[])
            .map(
              (stop) => {
                'id': stop.place.id,
                'routeProgress': stop.routeProgress,
                'category': stop.place.category.name,
              },
            )
            .toList(growable: false),
        'opportunities': opportunities
            .map(
              (opportunity) => {
                'id': opportunity.id,
                'title': opportunity.title,
                'kind': opportunity.kind.name,
                'scope': opportunity.geoScope.name,
                'score': opportunity.score,
                'confidence': opportunity.confidence,
                'startsAt': opportunity.startsAt.toUtc().toIso8601String(),
                'peaksAt': opportunity.peaksAt.toUtc().toIso8601String(),
                'expiresAt': opportunity.expiresAt.toUtc().toIso8601String(),
                if (opportunity.target != null)
                  'target': {
                    'id': opportunity.target!.id,
                    'name': opportunity.target!.name,
                    'kind': opportunity.target!.kind.name,
                    'coordinate': {
                      'latitude': opportunity.target!.coordinate.latitude,
                      'longitude': opportunity.target!.coordinate.longitude,
                      'system': 'wgs84',
                    },
                    'arrivalDeadline': opportunity.target!.arrivalDeadline
                        .toUtc()
                        .toIso8601String(),
                  },
                if (opportunity.corridor != null)
                  'corridor': {
                    'routeId': opportunity.corridor!.routeId,
                    'observations': opportunity.corridor!.observations
                        .map(
                          (item) => {
                            'progress': item.progress,
                            'expectedAt': item.expectedAt
                                .toUtc()
                                .toIso8601String(),
                            'condition': item.condition,
                            'cloudCoverPercent': item.cloudCoverPercent,
                            'windSpeedMps': item.windSpeedMps,
                            'precipitationMm': item.precipitationMm,
                            'thunder': item.thunder,
                            'sunAzimuthDegrees': item.sunAzimuthDegrees,
                            'opportunityId': item.opportunityId,
                          },
                        )
                        .toList(growable: false),
                  },
                'evidence': opportunity.evidence
                    .map(
                      (item) => {
                        'id': item.id,
                        'kind': item.kind.name,
                        'statement': item.statement,
                        'confidence': item.confidence,
                        'supports': item.supports,
                      },
                    )
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
      },
    );
    try {
      await ref
          .read(userLibraryProvider.notifier)
          .saveOfflinePhotographyPack(pack);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存到本机离线摄影包')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线摄影包未能保存，请重试')));
    }
  }

  IconData _timelineIcon(RouteTimelineKind kind) => switch (kind) {
    RouteTimelineKind.departure => Icons.trip_origin,
    RouteTimelineKind.safety => Icons.warning_amber_rounded,
    RouteTimelineKind.support => Icons.storefront_outlined,
    RouteTimelineKind.elevation => Icons.terrain_outlined,
    RouteTimelineKind.shooting => Icons.photo_camera_outlined,
    RouteTimelineKind.shootingMissed => Icons.schedule_outlined,
    RouteTimelineKind.arrival => Icons.flag_outlined,
    RouteTimelineKind.returnDeadline => Icons.timer_outlined,
    RouteTimelineKind.estimatedReturn => Icons.keyboard_return,
  };

  String _timelineTime(RouteTimelineEntry entry) {
    final start = _time(entry.time);
    final end = entry.end;
    return end == null ? start : '$start–${_time(end)}';
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _HikingReturnCard extends StatelessWidget {
  const _HikingReturnCard({required this.assessment});

  final HikingReturnAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final risk = assessment.risk;
    final message = switch (risk) {
      HikingReturnRisk.beforeSunset => '按原路同等耗时估算，立即返程可在日落前返回。',
      HikingReturnRisk.afterSunset => '按原路同等耗时估算，抵达后立即返程也可能晚于日落。',
      HikingReturnRisk.unknown => '缺少日落数据，仅能提供往返耗时参考。',
    };
    final latest = assessment.latestReturnDeparture;
    return Material(
      color: risk == HikingReturnRisk.afterSunset
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: const Icon(Icons.hiking_outlined),
        title: const Text('徒步返程参考'),
        subtitle: Text(
          latest == null
              ? '$message\n预计往返结束 ${_formatTime(assessment.estimatedReturnArrival)}'
              : '$message\n建议最晚 ${_formatTime(latest)} 开始返程',
        ),
        isThreeLine: true,
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SupportResults extends StatelessWidget {
  const _SupportResults({required this.stops});

  final List<RouteSupportStop> stops;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const Text('路线附近暂未找到可靠的加油、餐饮或补给点。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('沿途服务点', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final stop in stops)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              stop.place.category == NearbyPlaceCategory.fuel
                  ? Icons.local_gas_station_outlined
                  : stop.place.category == NearbyPlaceCategory.food
                  ? Icons.restaurant_outlined
                  : Icons.shopping_bag_outlined,
            ),
            title: Text(stop.place.name),
            subtitle: Text(
              '${stop.place.category.label} · 约在路线 ${(stop.routeProgress * 100).round()}% · 距采样点约 ${stop.place.distanceMeters} m${stop.isCached ? ' · 离线缓存' : ''}',
            ),
          ),
      ],
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _RouteErrorView extends StatelessWidget {
  const _RouteErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.route_outlined, size: 44),
        const SizedBox(height: 12),
        const Text('路线暂时无法生成'),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class _ImportedTrackUnavailableView extends StatelessWidget {
  const _ImportedTrackUnavailableView();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, size: 44),
        const SizedBox(height: 12),
        const Text('这条本地轨迹已不存在或无法读取'),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => context.go('/route'),
          child: const Text('返回路线'),
        ),
      ],
    ),
  );
}

class _ActiveTrackUnavailableView extends ConsumerWidget {
  const _ActiveTrackUnavailableView(this.journey);

  final SavedJourney journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('进行中的本地轨迹已不存在'),
          const SizedBox(height: 8),
          const Text('结束当前行程后，可以重新导入 GPX 轨迹。'),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _endUnavailableJourney(context, ref),
            child: const Text('结束行程并返回'),
          ),
        ],
      ),
    ),
  );

  Future<void> _endUnavailableJourney(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref.read(routeReminderServiceProvider).cancel(journey.id);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('系统返程提醒未能取消，行程仍保留')));
      return;
    }
    await ref
        .read(userLibraryProvider.notifier)
        .endJourney(journey.destination, routeKey: journey.routeKey);
    ref.read(routeContextStateProvider.notifier).end();
    ref.read(routeCorridorContextProvider.notifier).clear();
  }
}

/// Maps the route feature travel mode to the core context route mode.
ContextRouteMode _contextMode(RouteTravelMode mode) =>
    mode == RouteTravelMode.walking
    ? ContextRouteMode.hiking
    : ContextRouteMode.driving;

/// Synchronizes the route context state to [none] when the route page has no
/// destination. All writes happen in a post-frame callback so they never run
/// during build.
class _RouteNoneSync extends ConsumerStatefulWidget {
  const _RouteNoneSync({required this.child});

  final Widget child;

  @override
  ConsumerState<_RouteNoneSync> createState() => _RouteNoneSyncState();
}

class _RouteNoneSyncState extends ConsumerState<_RouteNoneSync> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routeContextStateProvider.notifier).end();
      ref.read(routeCorridorContextProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Honest lifecycle controls for route context following. These buttons drive
/// [routeContextStateProvider] so the environment snapshot pipeline can follow
/// the user's route. They do NOT provide turn-by-turn navigation.
class _RouteLifecycleBar extends ConsumerWidget {
  const _RouteLifecycleBar({
    required this.state,
    required this.destination,
    this.routeKey,
    this.returnReminderAt,
  });

  final RouteContextState state;
  final SavedRouteDestination destination;
  final String? routeKey;
  final DateTime? returnReminderAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(routeContextStateProvider.notifier);
    final hasRoute = state.hasRoute;
    final isActive = state.isActive;
    final isPaused = state.stage == ContextRouteStage.paused;
    final isPlanned = state.isPlanned;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive
                      ? Icons.near_me_rounded
                      : isPaused
                      ? Icons.pause_circle_outline
                      : Icons.radio_button_checked,
                  size: 18,
                  color: isActive
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('情境跟随', style: theme.textTheme.labelLarge),
                const Spacer(),
                Text(
                  isActive
                      ? '进行中'
                      : isPaused
                      ? '已暂停'
                      : '待出发',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '控制环境情境跟随路线，不提供逐向导航。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Start is only meaningful when a route is planned. A none
                // state (e.g. after ending the trip) must not offer a button
                // that start() cannot act on.
                if (isPlanned)
                  FilledButton.icon(
                    onPressed: () => _start(context, ref, notifier),
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('开始行程'),
                  ),
                if (isActive)
                  FilledButton.tonalIcon(
                    onPressed: () => notifier.pause(),
                    icon: const Icon(Icons.pause_outlined),
                    label: const Text('暂停'),
                  ),
                if (isPaused)
                  FilledButton.tonalIcon(
                    onPressed: () => notifier.resume(),
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('继续'),
                  ),
                if (isPlanned)
                  OutlinedButton(
                    onPressed: () {
                      notifier.end();
                      ref.read(routeCorridorContextProvider.notifier).clear();
                      // Cancel the planned route: leave the destination so the
                      // page and state stay consistent (no destination, none).
                      context.go('/route');
                    },
                    child: const Text('取消规划'),
                  ),
                if (hasRoute && !isPlanned)
                  OutlinedButton(
                    onPressed: () => _end(context, ref, notifier),
                    child: const Text('结束行程'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    RouteContextStateController notifier,
  ) async {
    try {
      final journey = await ref
          .read(userLibraryProvider.notifier)
          .startJourney(destination, routeKey: routeKey);
      notifier.start();
      try {
        final enabled = await ref.read(routeReminderEnabledProvider.future);
        final reminderAt = returnReminderAt;
        if (enabled && reminderAt != null) {
          final scheduled = await ref
              .read(routeReminderServiceProvider)
              .scheduleReturnReminder(
                journeyId: journey.id,
                destinationName: destination.name,
                scheduledAt: reminderAt,
              );
          if (!scheduled && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('最晚返程时间已过，本次未安排系统提醒')));
          }
        } else if (enabled &&
            destination.travelMode == 'walking' &&
            context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('缺少可用日落时间，本次未安排系统提醒')));
        }
      } on Object {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('行程已开始，但返程提醒未能安排')));
      }
    } on ActiveJourneyConflict catch (conflict) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '请先结束正在进行的“${conflict.activeJourney.destination.name}”',
          ),
        ),
      );
    } on Object {
      notifier.start();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('情境跟随已开始，但本地行程记录未能保存')));
    }
  }

  Future<void> _end(
    BuildContext context,
    WidgetRef ref,
    RouteContextStateController notifier,
  ) async {
    var recordFailed = false;
    var reminderCancelFailed = false;
    SavedJourney? active;
    try {
      active = (await ref.read(userLibraryProvider.future)).activeJourney;
      await ref
          .read(userLibraryProvider.notifier)
          .endJourney(destination, routeKey: routeKey);
    } on Object {
      recordFailed = true;
    }
    if (active != null && active.matches(destination, routeKey: routeKey)) {
      try {
        await ref.read(routeReminderServiceProvider).cancel(active.id);
      } on Object {
        reminderCancelFailed = true;
      }
    }
    notifier.end();
    ref.read(routeCorridorContextProvider.notifier).clear();
    if (!context.mounted) return;
    context.go('/route');
    if (recordFailed || reminderCancelFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recordFailed ? '行程已结束，但本地结束时间未能保存' : '行程已结束，但系统返程提醒未能取消',
          ),
        ),
      );
    }
  }
}
