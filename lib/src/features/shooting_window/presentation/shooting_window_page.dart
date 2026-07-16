import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_recovery.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';

/// Foreground-only execution surface for already-established opportunities.
///
/// It intentionally does not create facts, watch the device location, or keep
/// running in the background. When a V3 opportunity list is unavailable, the
/// page remains a local solar reference rather than pretending one exists.
class ShootingWindowPage extends ConsumerStatefulWidget {
  const ShootingWindowPage({
    super.key,
    this.snapshotAsync,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
    this.onRefresh,
    this.now,
    this.initialOpportunityId,
  });

  final AsyncValue<ContextSnapshot>? snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;

  /// Test seam; the live page refreshes its shared environment provider.
  final Future<void> Function()? onRefresh;
  final DateTime Function()? now;
  final String? initialOpportunityId;

  @override
  ConsumerState<ShootingWindowPage> createState() => _ShootingWindowPageState();
}

class _ShootingWindowPageState extends ConsumerState<ShootingWindowPage>
    with WidgetsBindingObserver {
  static const _refreshInterval = Duration(minutes: 3);
  Timer? _clock;
  Timer? _refreshTimer;
  DateTime _now = DateTime.now();
  String? _selectedOpportunityId;
  String? _watchingOpportunityId;
  bool _foreground = true;

  DateTime get _currentTime => widget.now?.call() ?? _now;

  @override
  void initState() {
    super.initState();
    _selectedOpportunityId = widget.initialOpportunityId;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ShootingWindowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialOpportunityId;
    if (next != null && next != oldWidget.initialOpportunityId) {
      _selectedOpportunityId = next;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _syncTimers();
    } else {
      _clock?.cancel();
      _refreshTimer?.cancel();
    }
  }

  void _syncTimers() {
    final watching = _watchingOpportunityId != null && _foreground;
    if (!watching) {
      _clock?.cancel();
      _clock = null;
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.now == null) setState(() => _now = DateTime.now());
    });
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!_foreground || _watchingOpportunityId == null) return;
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
      return;
    }
    if (widget.snapshotAsync == null) {
      await ref.read(environmentSnapshotProvider.notifier).refresh();
    }
  }

  Future<void> _startWatching(PhotographyOpportunity opportunity) async {
    setState(() => _watchingOpportunityId = opportunity.id);
    _syncTimers();
    await ref
        .read(userLibraryProvider.notifier)
        .watchOpportunity(
          opportunityId: opportunity.id,
          snapshotId: _snapshotId,
          title: opportunity.title,
          expiresAt: opportunity.expiresAt,
          targetId: opportunity.target?.id,
        );
  }

  String _snapshotId = '';

  Future<void> _endWatching(PhotographyOpportunity opportunity) async {
    final library = _libraryValue(ref.read(userLibraryProvider));
    final watched = library?.watchedOpportunities.where(
      (item) => item.opportunityId == opportunity.id,
    );
    for (final item in watched ?? const <WatchedPhotographyOpportunity>[]) {
      await ref.read(userLibraryProvider.notifier).unwatchOpportunity(item.id);
    }
    if (mounted) setState(() => _watchingOpportunityId = null);
    _syncTimers();
  }

  Future<void> _recordResult(
    PhotographyOpportunity opportunity,
    PhotographyOpportunityOutcome outcome,
  ) async {
    await ref
        .read(userLibraryProvider.notifier)
        .recordOpportunityResult(
          opportunityId: opportunity.id,
          snapshotId: _snapshotId,
          outcome: outcome,
          targetId: opportunity.target?.id,
        );
    await _endWatching(opportunity);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_resultLabel(outcome))));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ContextSnapshot> snapshot =
        widget.snapshotAsync ?? ref.watch(environmentSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('拍摄窗口')),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _WindowErrorView(
          error: error,
          onRetry:
              widget.onRetry ??
              (widget.snapshotAsync == null
                  ? () =>
                        ref.read(environmentSnapshotProvider.notifier).refresh()
                  : null),
          onOpenAppSettings:
              widget.onOpenAppSettings ??
              (widget.snapshotAsync == null
                  ? Geolocator.openAppSettings
                  : null),
          onSelectManualLocation:
              widget.onSelectManualLocation ??
              (widget.snapshotAsync == null
                  ? () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => const ManualLocationSheet(),
                    )
                  : null),
        ),
        data: (value) {
          _snapshotId = value.id;
          final library = _libraryValue(ref.watch(userLibraryProvider));
          final restoredWatch = _watchingOpportunityId == null
              ? library?.watchedOpportunities
                    .where(
                      (item) =>
                          item.expiresAt.isAfter(_currentTime) &&
                          value.photographyOpportunities.any(
                            (opportunity) =>
                                opportunity.id == item.opportunityId,
                          ),
                    )
                    .firstOrNull
              : null;
          if (restoredWatch != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _watchingOpportunityId != null) return;
              setState(
                () => _watchingOpportunityId = restoredWatch.opportunityId,
              );
              _syncTimers();
            });
          }
          return _ExecutionOrTimeline(
            snapshot: value,
            now: _currentTime,
            selectedOpportunityId: _selectedOpportunityId,
            watchingOpportunityId: _watchingOpportunityId,
            equipmentList: ref.watch(profilePreferencesProvider).equipmentList,
            library: library,
            onSelect: (id) => setState(() => _selectedOpportunityId = id),
            onStart: _startWatching,
            onEnd: _endWatching,
            onRefresh: _refresh,
            onRecord: _recordResult,
          );
        },
      ),
    );
  }
}

class _ExecutionOrTimeline extends StatelessWidget {
  const _ExecutionOrTimeline({
    required this.snapshot,
    required this.now,
    required this.selectedOpportunityId,
    required this.watchingOpportunityId,
    required this.equipmentList,
    required this.library,
    required this.onSelect,
    required this.onStart,
    required this.onEnd,
    required this.onRefresh,
    required this.onRecord,
  });

  final ContextSnapshot snapshot;
  final DateTime now;
  final String? selectedOpportunityId;
  final String? watchingOpportunityId;
  final String equipmentList;
  final UserLibraryState? library;
  final ValueChanged<String> onSelect;
  final Future<void> Function(PhotographyOpportunity) onStart;
  final Future<void> Function(PhotographyOpportunity) onEnd;
  final Future<void> Function() onRefresh;
  final Future<void> Function(
    PhotographyOpportunity,
    PhotographyOpportunityOutcome,
  )
  onRecord;

  @override
  Widget build(BuildContext context) {
    final opportunities =
        snapshot.photographyOpportunities
            .where((item) => !item.isExpiredAt(now))
            .toList(growable: false)
          ..sort((a, b) {
            final aActive = a.isActiveAt(now);
            final bActive = b.isActiveAt(now);
            if (aActive != bActive) return aActive ? -1 : 1;
            return a.startsAt.compareTo(b.startsAt);
          });
    if (opportunities.isEmpty) return _Timeline(snapshot: snapshot);
    final selected = opportunities.firstWhere(
      (item) => item.id == selectedOpportunityId,
      orElse: () => opportunities.first,
    );
    final persistedWatching =
        library?.watchedOpportunities.any(
          (item) =>
              item.opportunityId == selected.id && item.expiresAt.isAfter(now),
        ) ??
        false;
    final watching = watchingOpportunityId == selected.id || persistedWatching;
    final capabilities = EquipmentCapabilityParser.idsOf(
      EquipmentCapabilityParser.parse(equipmentList),
    );
    final decision = PhotographyDecisionResolver.resolve(
      selected,
      now: now,
      availableCapabilities: capabilities,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        if (opportunities.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in opportunities)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item.title),
                      selected: item.id == selected.id,
                      onSelected: (_) => onSelect(item.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _OpportunityHeader(opportunity: selected, now: now, decision: decision),
        const SizedBox(height: 18),
        _ExecutionFacts(snapshot: snapshot, opportunity: selected),
        const SizedBox(height: 18),
        if (watching)
          _WatchingControls(
            opportunity: selected,
            now: now,
            onEnd: onEnd,
            onRefresh: onRefresh,
            onRecord: onRecord,
          )
        else
          FilledButton.icon(
            key: const Key('start-watching'),
            onPressed: () => onStart(selected),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('开始守候'),
          ),
      ],
    );
  }
}

class _OpportunityHeader extends StatelessWidget {
  const _OpportunityHeader({
    required this.opportunity,
    required this.now,
    required this.decision,
  });

  final PhotographyOpportunity opportunity;
  final DateTime now;
  final PhotographyDecisionResolution decision;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('已成立机会', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 5),
      Text(
        opportunity.title,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        _countdownLabel(opportunity, now),
        key: const Key('opportunity-countdown'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 5),
      Text('${decision.actionLabel} · ${decision.score}% 匹配'),
    ],
  );
}

class _ExecutionFacts extends StatelessWidget {
  const _ExecutionFacts({required this.snapshot, required this.opportunity});
  final ContextSnapshot snapshot;
  final PhotographyOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final place = opportunity.evidence
        .where((item) => item.kind == PhotographyEvidenceKind.place)
        .map((item) => item.statement)
        .firstOrNull;
    final direction = snapshot.solarAzimuthDegrees == null
        ? null
        : _bearing(snapshot.solarAzimuthDegrees!);
    final directionDetail = switch ((direction, place)) {
      (final String value, final String location) => '光线方向 $value · $location',
      (final String value, null) => '光线方向 $value',
      (null, final String location) => location,
      (null, null) => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('守候依据', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final item in opportunity.evidence.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• ${item.statement}'),
          ),
        if (directionDetail != null) ...[
          const SizedBox(height: 6),
          Text(directionDetail, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (opportunity.requiredCapabilities.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '装备：${opportunity.requiredCapabilities.join('、')}',
            key: const Key('equipment-match'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _WatchingControls extends StatelessWidget {
  const _WatchingControls({
    required this.opportunity,
    required this.now,
    required this.onEnd,
    required this.onRefresh,
    required this.onRecord,
  });
  final PhotographyOpportunity opportunity;
  final DateTime now;
  final Future<void> Function(PhotographyOpportunity) onEnd;
  final Future<void> Function() onRefresh;
  final Future<void> Function(
    PhotographyOpportunity,
    PhotographyOpportunityOutcome,
  )
  onRecord;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(height: 32),
      Text('守候中 · 每 3 分钟更新条件', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('refresh-watching'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('更新条件'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('end-watching'),
              onPressed: () => onEnd(opportunity),
              child: const Text('结束守候'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Text('这次结果', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ResultButton(
            '拍到了',
            () => onRecord(opportunity, PhotographyOpportunityOutcome.shot),
          ),
          _ResultButton(
            '错过',
            () => onRecord(opportunity, PhotographyOpportunityOutcome.missed),
          ),
          _ResultButton(
            '跳过',
            () => onRecord(opportunity, PhotographyOpportunityOutcome.skipped),
          ),
        ],
      ),
    ],
  );
}

class _ResultButton extends StatelessWidget {
  const _ResultButton(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) =>
      OutlinedButton(onPressed: onPressed, child: Text(label));
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
    if (windows.isEmpty) return const Center(child: Text('当前位置暂时没有可计算的日出日落窗口'));
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
}

String _countdownLabel(PhotographyOpportunity opportunity, DateTime now) {
  if (opportunity.isActiveAt(now)) {
    final untilPeak = opportunity.peaksAt.difference(now);
    if (!untilPeak.isNegative && untilPeak != Duration.zero) {
      return '${_duration(untilPeak)} 后达峰值';
    }
    return '窗口进行中 · ${_duration(opportunity.expiresAt.difference(now))} 后结束';
  }
  return '${_duration(opportunity.startsAt.difference(now))} 后开始';
}

String _duration(Duration value) {
  final minutes = value.isNegative ? 0 : value.inMinutes;
  if (minutes < 60) return '$minutes 分钟';
  return '${minutes ~/ 60} 小时${minutes % 60 == 0 ? '' : '${minutes % 60} 分'}';
}

String _bearing(double degrees) {
  const labels = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  final index = (((degrees % 360) + 22.5) ~/ 45) % labels.length;
  return labels[index];
}

String _resultLabel(PhotographyOpportunityOutcome outcome) => switch (outcome) {
  PhotographyOpportunityOutcome.shot => '已记下这次拍摄',
  PhotographyOpportunityOutcome.missed => '已记下这次错过',
  PhotographyOpportunityOutcome.skipped => '已记下这次跳过',
};

UserLibraryState? _libraryValue(AsyncValue<UserLibraryState> value) => value
    .when(data: (data) => data, loading: () => null, error: (_, _) => null);

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
