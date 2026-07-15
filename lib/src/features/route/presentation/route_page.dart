import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
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
      return _RouteNoneSync(
        child: ref
            .watch(userLibraryProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _EmptyRouteView(),
              data: (_) => const _EmptyRouteView(),
            ),
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
    final importedTracks = library?.importedTracks ?? const [];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LumaNestSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.route_outlined, size: LumaNestSpacing.xl),
            const SizedBox(height: LumaNestSpacing.lg),
            Text('路线', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: LumaNestSpacing.sm),
            const Text('从探索页选择目的地生成路线，也可以导入已有 GPX 轨迹离线查看。'),
            const SizedBox(height: LumaNestSpacing.lg),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/explore'),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('去探索目的地'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.go('/explore'),
                  icon: const Icon(Icons.add_road_outlined),
                  label: const Text('创建路线'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _importing ? null : _importTrack,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(_importing ? '正在导入' : '导入轨迹'),
                ),
              ],
            ),
            const SizedBox(height: LumaNestSpacing.lg),
            Text('历史路线', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (recentRoute != null)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(recentRoute.name),
                trailing: const Icon(Icons.arrow_outward),
                onTap: () => context.go(_routeUri(recentRoute).toString()),
              ),
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
            if (recentRoute == null && importedTracks.isEmpty)
              const Text('暂无历史路线'),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(routeContextStateProvider.notifier)
          .plan(
            _contextMode(widget.travelMode),
            identity: RouteIdentity(
              latitude: widget.destinationLatitude,
              longitude: widget.destinationLongitude,
              mode: _contextMode(widget.travelMode),
              routeKey: widget.route.sourceId,
            ),
          );
    });
  }

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
    final distance = route.distanceMeters >= 1000
        ? '${(route.distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${route.distanceMeters} m';
    final duration = Duration(seconds: route.durationSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationLabel = hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
    final routeState = ref.watch(routeContextStateProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Text('路线', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          route.source == RouteSource.importedGpx
              ? route.destinationName
              : '前往 ${route.destinationName}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        _RouteLifecycleBar(state: routeState),
        if (route.source != RouteSource.importedGpx && !route.isStale) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _openAmapNavigation,
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('交给高德导航'),
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _RouteMetric(label: '距离', value: distance),
                ),
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
          const Text('补给时间按路线进度估算；拍摄窗口使用当前地点日月数据，未推断沿途未来天气和地形遮挡。'),
          const SizedBox(height: 10),
          for (final entry in timeline)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_timelineIcon(entry.kind)),
              title: Text(entry.label),
              subtitle: Text(entry.description),
              trailing: Text(_timelineTime(entry)),
            ),
        ],
        const SizedBox(height: 22),
        Text('路线步骤', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (route.instructions.isEmpty)
          Text(
            route.source == RouteSource.importedGpx
                ? 'GPX 仅包含轨迹线，不含道路转向说明。'
                : '路线已生成，暂时没有详细道路说明。',
          )
        else
          for (
            var index = 0;
            index < route.instructions.length && index < 8;
            index++
          )
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              title: Text(route.instructions[index]),
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

  IconData _timelineIcon(RouteTimelineKind kind) => switch (kind) {
    RouteTimelineKind.departure => Icons.trip_origin,
    RouteTimelineKind.safety => Icons.warning_amber_rounded,
    RouteTimelineKind.support => Icons.storefront_outlined,
    RouteTimelineKind.elevation => Icons.terrain_outlined,
    RouteTimelineKind.shooting => Icons.photo_camera_outlined,
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
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Honest lifecycle controls for route context following. These buttons drive
/// [routeContextStateProvider] so the environment snapshot pipeline can follow
/// the user's route. They do NOT provide turn-by-turn navigation.
class _RouteLifecycleBar extends ConsumerWidget {
  const _RouteLifecycleBar({required this.state});

  final RouteContextState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(routeContextStateProvider.notifier);
    final hasRoute = state.hasRoute;
    final isActive = state.isActive;
    final isPaused = state.stage == ContextRouteStage.paused;
    final isPlanned = state.isPlanned;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('情境跟随', style: Theme.of(context).textTheme.labelMedium),
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
                    onPressed: () => notifier.start(),
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
                      // Cancel the planned route: leave the destination so the
                      // page and state stay consistent (no destination, none).
                      context.go('/route');
                    },
                    child: const Text('取消规划'),
                  ),
                if (hasRoute && !isPlanned)
                  OutlinedButton(
                    onPressed: () {
                      notifier.end();
                      // Leave the destination route so the page and state stay
                      // consistent: no destination, none state.
                      context.go('/route');
                    },
                    child: const Text('结束行程'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
