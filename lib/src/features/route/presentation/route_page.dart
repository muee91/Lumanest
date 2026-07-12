import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/application/route_corridor_scanner.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

class RoutePage extends ConsumerWidget {
  const RoutePage({
    super.key,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  final String? destinationName;
  final double? destinationLatitude;
  final double? destinationLongitude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (destinationName == null ||
        destinationLatitude == null ||
        destinationLongitude == null) {
      return _EmptyRouteView(onExplore: () => context.go('/explore'));
    }
    final destination = RouteDestination(
      name: destinationName!,
      point: GeoPoint(
        latitude: destinationLatitude!,
        longitude: destinationLongitude!,
        coordinateSystem: CoordinateSystem.gcj02,
      ),
    );
    final route = ref.watch(drivingRouteProvider(destination));
    return SafeArea(
      child: route.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _RouteErrorView(
          onRetry: () => ref.invalidate(drivingRouteProvider(destination)),
        ),
        data: (value) => _RouteContent(route: value),
      ),
    );
  }
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
  const _RouteContent({required this.route});

  final DrivingRoute route;

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
                    label: '过路费',
                    value: route.tollsYuan > 0
                        ? '¥${route.tollsYuan.toStringAsFixed(0)}'
                        : '无',
                  ),
                ),
              ],
            ),
          ),
        ),
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
          icon: const Icon(Icons.local_gas_station_outlined),
          label: Text(_support == null ? '扫描沿途加油和补给' : '重新扫描沿途补给'),
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
