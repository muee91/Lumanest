import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/application/route_corridor_scanner.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_timeline.dart';
import 'package:luma_nest/src/features/route/domain/hiking_return_assessment.dart';
import 'package:luma_nest/src/features/route/presentation/route_map_preview.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

class RoutePage extends ConsumerWidget {
  const RoutePage({
    super.key,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
    this.routeAsync,
    this.contextSnapshot,
    this.timelineNow,
    this.routeMapBuilder,
    this.travelMode = RouteTravelMode.driving,
  });

  final String? destinationName;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final AsyncValue<DrivingRoute>? routeAsync;
  final ContextSnapshot? contextSnapshot;
  final DateTime? timelineNow;
  final RouteMapBuilder? routeMapBuilder;
  final RouteTravelMode travelMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (destinationName == null ||
        destinationLatitude == null ||
        destinationLongitude == null) {
      return ref
          .watch(userLibraryProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                _EmptyRouteView(onExplore: () => context.go('/explore')),
            data: (library) {
              final recent = library.recentRoute;
              if (recent == null) {
                return _EmptyRouteView(onExplore: () => context.go('/explore'));
              }
              return _buildRoute(
                context,
                ref,
                SavedRouteDestination(
                  name: recent.name,
                  latitude: recent.latitude,
                  longitude: recent.longitude,
                  travelMode: recent.travelMode,
                ),
                mode: recent.travelMode == RouteTravelMode.walking.name
                    ? RouteTravelMode.walking
                    : RouteTravelMode.driving,
              );
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

class _EmptyRouteView extends StatelessWidget {
  const _EmptyRouteView({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(LumaNestSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.route_outlined, size: LumaNestSpacing.xl),
          const SizedBox(height: LumaNestSpacing.lg),
          Text('路线', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: LumaNestSpacing.sm),
          const Text('从探索页选择机位、加油站或补给点，栖光会从当前位置生成路线。'),
          const Spacer(),
          FilledButton.icon(
            onPressed: onExplore,
            icon: const Icon(Icons.explore_outlined),
            label: const Text('去探索目的地'),
          ),
        ],
      ),
    ),
  );
}

class _RouteContent extends ConsumerStatefulWidget {
  const _RouteContent({
    required this.route,
    required this.snapshot,
    required this.departureAt,
    required this.routeMapBuilder,
  });

  final DrivingRoute route;
  final ContextSnapshot? snapshot;
  final DateTime departureAt;
  final RouteMapBuilder? routeMapBuilder;

  @override
  ConsumerState<_RouteContent> createState() => _RouteContentState();
}

class _RouteContentState extends ConsumerState<_RouteContent> {
  AsyncValue<List<NearbyPlace>>? _support;

  Future<void> _scanSupport() async {
    setState(() => _support = const AsyncLoading());
    final scanner = RouteCorridorScanner(
      ref.read(nearbyPlaceRepositoryProvider),
    );
    final result = await AsyncValue.guard(() => scanner.scan(widget.route));
    if (mounted) setState(() => _support = result);
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final snapshot = widget.snapshot;
    final safety = snapshot == null
        ? const <ManifestItem>[]
        : ManifestPolicy.build(snapshot, now: widget.departureAt).safety;
    final timeline = snapshot == null
        ? const <RouteTimelineEntry>[]
        : RouteTimeline.build(
            route: route,
            snapshot: snapshot,
            departureAt: widget.departureAt,
          );
    final hikingAssessment = snapshot == null
        ? null
        : HikingReturnAssessment.build(
            route: route,
            snapshot: snapshot,
            departureAt: widget.departureAt,
          );
    final distance = route.distanceMeters >= 1000
        ? '${(route.distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${route.distanceMeters} m';
    final duration = Duration(seconds: route.durationSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationLabel = hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Text('路线', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '前往 ${route.destinationName}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
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
                  child: _RouteMetric(label: '预计', value: durationLabel),
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
            '高程来源：$source · 采样估算，不替代专业测绘',
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
          const Text('拍摄窗口按当前地点的日月时间计算，未包含沿途地形遮挡和未来天气变化。'),
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
          const Text('路线已生成，暂时没有详细道路说明。')
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
                      ? '扫描沿途补给'
                      : '扫描沿途加油和补给'
                : '重新扫描沿途补给',
          ),
        ),
        if (_support case final support?) ...[
          const SizedBox(height: 14),
          support.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('沿途补给数据暂时不可用'),
            data: (items) => _SupportResults(items: items),
          ),
        ],
      ],
    );
  }

  IconData _timelineIcon(RouteTimelineKind kind) => switch (kind) {
    RouteTimelineKind.departure => Icons.trip_origin,
    RouteTimelineKind.shooting => Icons.photo_camera_outlined,
    RouteTimelineKind.arrival => Icons.flag_outlined,
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
  const _SupportResults({required this.items});

  final List<NearbyPlace> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('路线附近暂未找到可靠的加油站或超市。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('沿途补给', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final place in items.take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              place.category == NearbyPlaceCategory.fuel
                  ? Icons.local_gas_station_outlined
                  : Icons.shopping_bag_outlined,
            ),
            title: Text(place.name),
            subtitle: Text(
              '${place.category.label} · 距采样点约 ${place.distanceMeters} m',
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
