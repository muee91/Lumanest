import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_recovery.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';

class ShootingWindowPage extends ConsumerWidget {
  const ShootingWindowPage({
    super.key,
    this.snapshotAsync,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
  });

  final AsyncValue<ContextSnapshot>? snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ContextSnapshot> snapshot =
        snapshotAsync ?? ref.watch(environmentSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('拍摄窗口')),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _WindowErrorView(
          error: error,
          onRetry:
              onRetry ??
              (snapshotAsync == null
                  ? () =>
                        ref.read(environmentSnapshotProvider.notifier).refresh()
                  : null),
          onOpenAppSettings:
              onOpenAppSettings ??
              (snapshotAsync == null ? Geolocator.openAppSettings : null),
          onSelectManualLocation:
              onSelectManualLocation ??
              (snapshotAsync == null
                  ? () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => const ManualLocationSheet(),
                    )
                  : null),
        ),
        data: (value) => _Timeline(snapshot: value),
      ),
    );
  }
}

class _WindowErrorView extends StatelessWidget {
  const _WindowErrorView({
    required this.error,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
  });

  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied = isPermanentlyDeniedLocationFailure(error);
    final primaryAction = permanentlyDenied
        ? onOpenAppSettings ?? onRetry
        : onRetry;
    final primaryLabel = permanentlyDenied && onOpenAppSettings != null
        ? '打开设置'
        : '重试';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('暂时无法读取拍摄窗口'),
          if (primaryAction != null || onSelectManualLocation != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (primaryAction case final action?)
                  FilledButton.tonal(
                    onPressed: action,
                    child: Text(primaryLabel),
                  ),
                if (onSelectManualLocation case final action?)
                  OutlinedButton(
                    onPressed: action,
                    child: const Text('手动选择地点'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.snapshot});
  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final windows = ShootingWindowTimeline.build(snapshot);
    if (windows.isEmpty) {
      return const Center(child: Text('当前位置暂时没有可计算的日出日落窗口'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text('今日参考时间轴', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('时间由当前位置与太阳位置计算，不包含山体、建筑遮挡和临时天气变化。'),
        const SizedBox(height: 20),
        for (final window in windows)
          Card(
            color: window.isActiveAt(snapshot.observedAt)
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: ListTile(
              leading: Icon(
                window.id == 'dawn'
                    ? Icons.wb_twilight
                    : window.id == 'sunset'
                    ? Icons.wb_sunny_outlined
                    : Icons.nights_stay_outlined,
              ),
              title: Text(window.label),
              subtitle: Text(
                '${_time(window.start)}–${_time(window.end)}\n${window.description}',
              ),
              isThreeLine: true,
              trailing: window.isActiveAt(snapshot.observedAt)
                  ? const Chip(label: Text('当前'))
                  : null,
            ),
          ),
      ],
    );
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
