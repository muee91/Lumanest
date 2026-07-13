import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';

class ShootingWindowPage extends ConsumerWidget {
  const ShootingWindowPage({super.key, this.snapshotAsync});

  final AsyncValue<ContextSnapshot>? snapshotAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ContextSnapshot> snapshot =
        snapshotAsync ?? ref.watch(environmentSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('拍摄窗口')),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('暂时无法读取拍摄窗口')),
        data: (value) => _Timeline(snapshot: value),
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
