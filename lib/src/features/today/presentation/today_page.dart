import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/environment_recovery.dart';
import 'package:luma_nest/src/core/context/safety_detail.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';
import 'package:luma_nest/src/features/location/application/manual_location_providers.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_brand_mark.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_surface.dart';
import 'package:luma_nest/src/shared/widgets/manifest_event_metadata.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.snapshotAsync,
    this.onRetry,
    this.onRefresh,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
    this.onClearManualLocation,
    this.onManifestAction,
    this.narrativeAsync,
    this.manifest,
    this.locationDisplay = const EnvironmentLocationDisplay.device(),
  });

  final AsyncValue<ContextSnapshot> snapshotAsync;
  final VoidCallback? onRetry;

  /// Completes only after the latest environment snapshot has been resolved.
  /// Keeping this separate from [onRetry] preserves the compact error actions
  /// while letting pull-to-refresh hold its progress affordance on screen.
  final Future<void> Function()? onRefresh;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;
  final VoidCallback? onClearManualLocation;
  final ValueChanged<ManifestItem>? onManifestAction;
  final AsyncValue<ManifestNarrative>? narrativeAsync;
  final UiManifest? manifest;
  final EnvironmentLocationDisplay locationDisplay;

  @override
  Widget build(BuildContext context) {
    return snapshotAsync.when(
      data: (snapshot) => _buildContent(context, snapshot),
      loading: () => _buildLoading(),
      error: (error, _) => _buildError(context, error),
    );
  }

  Widget _buildLoading() {
    return const SafeArea(child: Center(child: CircularProgressIndicator()));
  }

  Widget _buildError(BuildContext context, Object error) {
    final message = _errorMessage(error);
    final permanentlyDenied = isPermanentlyDeniedLocationFailure(error);
    final primaryAction = permanentlyDenied
        ? onOpenAppSettings ?? onRetry
        : onRetry;
    final primaryLabel = permanentlyDenied && onOpenAppSettings != null
        ? '打开设置'
        : '重试';
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(message, style: Theme.of(context).textTheme.bodyLarge),
              if (primaryAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: primaryAction,
                  child: Text(primaryLabel),
                ),
              ],
              if (error is EnvironmentLoadFailure &&
                  error.kind == EnvironmentFailureKind.location &&
                  onSelectManualLocation != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSelectManualLocation,
                  child: const Text('手动选择地点'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ContextSnapshot snapshot) {
    final effectiveManifest = manifest ?? ManifestPolicy.build(snapshot);
    final primary = effectiveManifest.primary;
    final photographyOpportunity = _primaryPhotographyOpportunity(snapshot);
    void performAction(ManifestItem item) {
      final injected = onManifestAction;
      if (injected != null) {
        injected(item);
      } else {
        handleManifestAction(context, item);
      }
    }

    final refresh = onRefresh;
    final list = ListView(
      key: const Key('today-scroll-view'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        LumaNestSpacing.md,
        LumaNestSpacing.sm,
        LumaNestSpacing.md,
        LumaNestSpacing.xl,
      ),
      children: [
        _TodayMasthead(
          snapshot: snapshot,
          locationDisplay: locationDisplay,
          onSelectManualLocation: onSelectManualLocation,
          onClearManualLocation: onClearManualLocation,
        ),
        const SizedBox(height: LumaNestSpacing.sm),
        _DecisionHero(
          dayPhase: snapshot.dayPhase,
          snapshot: snapshot,
          primary: primary,
          photographyOpportunity: photographyOpportunity,
        ),
        if (_shouldShowEnvironmentContext(snapshot, primary)) ...[
          const SizedBox(height: LumaNestSpacing.sm),
          _EvidenceMetrics(snapshot: snapshot, primary: primary),
        ],
        if (photographyOpportunity case final opportunity?) ...[
          const SizedBox(height: LumaNestSpacing.md),
          _PhotographyOpportunityAction(opportunity: opportunity),
        ] else if (primary case final primary?) ...[
          const SizedBox(height: LumaNestSpacing.md),
          _PrimaryActionBar(
            key: const Key('primary-opportunity'),
            item: primary,
            onTap: () => performAction(primary),
          ),
        ],
        _LightTimeline(snapshot: snapshot),
        if (effectiveManifest.safety.isNotEmpty) ...[
          const SizedBox(height: LumaNestSpacing.md),
          _SafetyRegion(
            items: effectiveManifest.safety,
            onAction: performAction,
          ),
        ],
        if (effectiveManifest.secondary.isNotEmpty) ...[
          const SizedBox(height: LumaNestSpacing.sm),
          _EditorialRule(label: '备用观察'),
          const SizedBox(height: LumaNestSpacing.xs),
          Column(
            key: const Key('secondary-opportunities'),
            children: [
              for (final item in effectiveManifest.secondary)
                Padding(
                  padding: const EdgeInsets.only(bottom: LumaNestSpacing.xs),
                  child: _AlternateOpportunity(
                    item: item,
                    onTap: () => performAction(item),
                  ),
                ),
            ],
          ),
        ],
        if (effectiveManifest.inspirationPreview.isNotEmpty) ...[
          const SizedBox(height: LumaNestSpacing.md),
          _InspirationTeaser(
            note: effectiveManifest.inspirationPreview,
            onTap: () => context.go('/inspiration'),
          ),
        ],
        if (primary == null) ...[
          const SizedBox(height: LumaNestSpacing.md),
          _QuietContextAction(onExplore: () => context.go('/explore')),
        ],
      ],
    );

    return SafeArea(
      child: refresh == null
          ? list
          : RefreshIndicator(
              key: const Key('today-environment-refresh'),
              color: Theme.of(context).colorScheme.secondary,
              displacement: 56,
              semanticsLabel: '正在刷新环境数据',
              onRefresh: refresh,
              child: list,
            ),
    );
  }

  static bool _shouldShowEnvironmentContext(
    ContextSnapshot snapshot,
    ManifestItem? primary,
  ) => switch (primary?.id) {
    'reflection' => snapshot.windSpeedMetersPerSecond != null,
    'mist' => snapshot.visibilityKilometers != null,
    'dust-light' => snapshot.windSpeedMetersPerSecond != null,
    'alpenglow' || 'blue-hour' => snapshot.visibilityKilometers != null,
    _ => false,
  };

  static PhotographyOpportunity? _primaryPhotographyOpportunity(
    ContextSnapshot snapshot,
  ) {
    final now = snapshot.observedAt;
    final opportunities =
        snapshot.photographyOpportunities
            .where((item) => !item.isExpiredAt(now))
            .toList(growable: false)
          ..sort((first, second) {
            final scoreOrder = second.score.compareTo(first.score);
            return scoreOrder != 0
                ? scoreOrder
                : first.startsAt.compareTo(second.startsAt);
          });
    return opportunities.firstOrNull;
  }

  static String _errorMessage(Object error) {
    if (error is EnvironmentLoadFailure) {
      return switch (error.kind) {
        EnvironmentFailureKind.configMissing => '环境配置未就绪',
        EnvironmentFailureKind.location => '无法获取位置信息',
        EnvironmentFailureKind.weather => '天气数据获取失败',
      };
    }
    return '数据加载失败';
  }
}

class _TodayMasthead extends StatelessWidget {
  const _TodayMasthead({
    required this.snapshot,
    required this.locationDisplay,
    this.onSelectManualLocation,
    this.onClearManualLocation,
  });
  final ContextSnapshot snapshot;
  final EnvironmentLocationDisplay locationDisplay;
  final VoidCallback? onSelectManualLocation;
  final VoidCallback? onClearManualLocation;

  @override
  Widget build(BuildContext context) {
    final scene = switch (snapshot.primaryScene) {
      SceneType.city => '城市观察',
      SceneType.lake => '湖岸光线',
      SceneType.mountain => '山地光线',
      SceneType.desert => '荒野纹理',
      SceneType.village => '人文漫游',
      SceneType.driving => '在路上',
      SceneType.hiking => '徒步中',
      SceneType.unknown => '此刻环境',
    };
    final theme = Theme.of(context);
    final hasPlaceName =
        locationDisplay.label.trim().isNotEmpty &&
        locationDisplay.label != '当前位置';
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(snapshot.observedAt.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const LumaNestBrandMark(size: 21),
            const SizedBox(width: 7),
            Expanded(child: Text('栖光', style: theme.textTheme.titleLarge)),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .78,
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: .75,
                  ),
                ),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(scene, style: theme.textTheme.labelLarge),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (hasPlaceName) ...[
              Icon(
                locationDisplay.isReference
                    ? Icons.location_on_outlined
                    : Icons.my_location_outlined,
                size: 15,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  locationDisplay.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: locationDisplay.isReference
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            if (onSelectManualLocation != null)
              TextButton.icon(
                key: const Key('today-manual-location'),
                onPressed: locationDisplay.isReference
                    ? onClearManualLocation
                    : onSelectManualLocation,
                icon: Icon(
                  locationDisplay.isReference
                      ? Icons.my_location_outlined
                      : Icons.edit_location_alt_outlined,
                  size: 16,
                ),
                label: Text(locationDisplay.isReference ? '恢复定位' : '选点'),
              ),
          ],
        ),
        if (snapshot.isStale)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _StaleLabel(compact: true),
          ),
      ],
    );
  }
}

class _DecisionHero extends StatelessWidget {
  const _DecisionHero({
    required this.dayPhase,
    required this.snapshot,
    required this.primary,
    this.photographyOpportunity,
  });
  final DayPhase dayPhase;
  final ContextSnapshot snapshot;
  final ManifestItem? primary;
  final PhotographyOpportunity? photographyOpportunity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (dayPhase) {
      DayPhase.dawn => '晨光判断',
      DayPhase.day => '今日判断',
      DayPhase.sunset => '落日判断',
      DayPhase.blueHour => '蓝调判断',
      DayPhase.night => '夜间判断',
    };
    final window = _currentOrNextWindow(snapshot);
    final verdict =
        photographyOpportunity?.title ?? primary?.title ?? '暂无明确拍摄窗口';
    return Semantics(
      container: true,
      label: '$label，$verdict',
      child: Padding(
        key: const Key('today-environment-hero'),
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _dayPhaseIcon(dayPhase),
                  size: 17,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  window == null ? '此刻' : _windowCaption(window, context),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              verdict,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(height: 1.08),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _dayPhaseIcon(DayPhase phase) => switch (phase) {
    DayPhase.dawn => Icons.wb_twilight_rounded,
    DayPhase.day => Icons.wb_sunny_outlined,
    DayPhase.sunset => Icons.wb_twilight_outlined,
    DayPhase.blueHour => Icons.brightness_2_outlined,
    DayPhase.night => Icons.nightlight_round,
  };

  static ShootingWindow? _currentOrNextWindow(ContextSnapshot snapshot) {
    final now = snapshot.observedAt;
    final windows = ShootingWindowTimeline.build(snapshot);
    for (final window in windows) {
      if (window.isActiveAt(now) || window.end.isAfter(now)) return window;
    }
    return null;
  }

  static String _windowCaption(ShootingWindow window, BuildContext context) =>
      '${TimeOfDay.fromDateTime(window.start.toLocal()).format(context)} ${window.label}';
}

class _QuietContextAction extends StatelessWidget {
  const _QuietContextAction({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.hourglass_empty_rounded, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text('暂无明确窗口', style: Theme.of(context).textTheme.bodyMedium),
        ),
        TextButton(onPressed: onExplore, child: const Text('探索附近')),
      ],
    ),
  );
}

class _EditorialRule extends StatelessWidget {
  const _EditorialRule({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(letterSpacing: 1.2),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ],
  );
}

class _LightTimeline extends StatelessWidget {
  const _LightTimeline({required this.snapshot});
  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final windows = ShootingWindowTimeline.build(snapshot);
    if (windows.isEmpty) return const SizedBox.shrink();
    String time(DateTime value) =>
        TimeOfDay.fromDateTime(value.toLocal()).format(context);
    return Padding(
      padding: const EdgeInsets.only(top: LumaNestSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _EditorialRule(label: '今日光线'),
          const SizedBox(height: LumaNestSpacing.sm),
          Semantics(
            label: '今日光线时间线',
            child: SingleChildScrollView(
              key: const Key('today-light-timeline'),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final window in windows)
                    Container(
                      width: 128,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: .72),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            time(window.start),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            window.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceMetrics extends StatelessWidget {
  const _EvidenceMetrics({required this.snapshot, required this.primary});
  final ContextSnapshot snapshot;
  final ManifestItem? primary;

  @override
  Widget build(BuildContext context) {
    final entries = _relevantEvidence(snapshot, primary);
    if (entries.isEmpty) return const SizedBox.shrink();
    return _EnvironmentMetrics(entries: entries);
  }

  static List<(IconData, String, String)> _relevantEvidence(
    ContextSnapshot snapshot,
    ManifestItem? primary,
  ) {
    final candidates = <(IconData, String, String)>[
      if (snapshot.windSpeedMetersPerSecond case final value?)
        (Icons.air_outlined, '${value.toStringAsFixed(1)} m/s', '风'),
      if (snapshot.visibilityKilometers case final value?)
        (Icons.visibility_outlined, '${value.round()} km', '能见度'),
      if (snapshot.cloudCoverPercent case final value?)
        (Icons.cloud_outlined, '${value.round()}%', '云量'),
      if (snapshot.temperatureCelsius case final value?)
        (Icons.device_thermostat_outlined, '${value.round()}°', '气温'),
    ];
    final preferred = switch (primary?.id) {
      'reflection' => const ['风', '能见度', '云量'],
      'mist' => const ['能见度', '气温', '风'],
      'dust-light' => const ['风', '能见度', '云量'],
      'alpenglow' || 'blue-hour' => const ['云量', '能见度', '风'],
      _ => const <String>[],
    };
    return [
      for (final label in preferred)
        ...candidates.where((entry) => entry.$3 == label),
    ].take(3).toList(growable: false);
  }
}

class _EnvironmentMetrics extends StatelessWidget {
  const _EnvironmentMetrics({required this.entries});

  final List<(IconData, String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (textScale >= 1.3 && entries.length > 2) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / 2;
          return Wrap(
            runSpacing: LumaNestSpacing.sm,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: itemWidth,
                  child: _MetricPill(
                    icon: entry.$1,
                    value: entry.$2,
                    label: entry.$3,
                  ),
                ),
            ],
          );
        },
      );
    }
    return Row(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          Expanded(
            child: _MetricPill(
              icon: entries[index].$1,
              value: entries[index].$2,
              label: entries[index].$3,
            ),
          ),
          if (index != entries.length - 1)
            Container(
              width: 1,
              height: 42,
              color: theme.colorScheme.outlineVariant.withValues(alpha: .7),
            ),
        ],
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _InspirationTeaser extends StatelessWidget {
  const _InspirationTeaser({required this.note, required this.onTap});
  final String note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => LumaNestSurface(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
    child: Row(
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 19,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            note,
            key: const Key('inspiration-preview'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Icon(Icons.arrow_forward_rounded, size: 18),
      ],
    ),
  );
}

/// Runtime entry point for Today. It keeps the privacy choice ahead of the
/// platform location prompt and only starts the live provider after consent.
class LiveTodayPage extends ConsumerWidget {
  const LiveTodayPage({super.key, this.initialSnapshot});

  /// Test and preview-only snapshot injection. Normal runtime leaves this
  /// null and never substitutes fixture data for live environment data.
  final ContextSnapshot? initialSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSnapshot case final snapshot?) {
      return TodayPage(
        snapshotAsync: AsyncData(snapshot),
        manifest: ref.watch(personalizedManifestProvider(snapshot)),
        narrativeAsync: ref.watch(manifestNarrativeProvider(snapshot)),
        onManifestAction: (item) =>
            unawaited(_handleAction(context, ref, snapshot, item)),
      );
    }

    final granted = ref.watch(environmentConsentProvider);
    if (!granted) {
      return _EnvironmentConsentPrompt(
        onGrant: () => ref.read(environmentConsentProvider.notifier).grant(),
      );
    }

    final snapshot = ref.watch(environmentSnapshotProvider);
    final narrative = snapshot.asData == null
        ? null
        : ref.watch(manifestNarrativeProvider(snapshot.requireValue));
    return TodayPage(
      snapshotAsync: snapshot,
      manifest: snapshot.asData == null
          ? null
          : ref.watch(personalizedManifestProvider(snapshot.requireValue)),
      narrativeAsync: narrative,
      locationDisplay: ref.watch(environmentLocationDisplayProvider),
      onRetry: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
      onRefresh: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
      onOpenAppSettings: Geolocator.openAppSettings,
      onSelectManualLocation: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const ManualLocationSheet(),
      ),
      onClearManualLocation: () {
        ref.read(manualLocationProvider.notifier).clear();
        unawaited(ref.read(environmentSnapshotProvider.notifier).refresh());
      },
      onManifestAction: snapshot.asData == null
          ? null
          : (item) => unawaited(
              _handleAction(context, ref, snapshot.requireValue, item),
            ),
    );
  }

  static Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    ContextSnapshot snapshot,
    ManifestItem item,
  ) async {
    if (item.action != ManifestAction.openSafety ||
        item.source != ContextEventSource.official) {
      await handleManifestAction(context, item);
      return;
    }

    SafetyDetail? detail;
    try {
      detail = await ref
          .read(safetyDetailRepositoryProvider)
          ?.fetch(contextId: snapshot.id, eventId: item.id);
    } on Object {
      detail = null;
    }
    if (!context.mounted) return;
    await handleManifestAction(
      context,
      item,
      detailOverride: detail?.description,
      guidance: detail?.guidance ?? const [],
    );
  }
}

class _EnvironmentConsentPrompt extends StatelessWidget {
  const _EnvironmentConsentPrompt({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('从当前位置开始', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('允许后，栖光会使用当前位置和天气生成此刻的拍摄建议。'),
              const SizedBox(height: 16),
              FilledButton(onPressed: onGrant, child: const Text('同意并继续')),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaleLabel extends StatelessWidget {
  const _StaleLabel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 14,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(width: 4),
          Text(
            '数据已过期',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyRegion extends StatelessWidget {
  const _SafetyRegion({required this.items, required this.onAction});

  final List<ManifestItem> items;
  final ValueChanged<ManifestItem> onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('safety-region'),
      container: true,
      label: '安全提醒',
      child: Material(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: .96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: .28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '安全提醒',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      letterSpacing: .8,
                    ),
                  ),
                  const Spacer(),
                  Text('独立通道', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 6),
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(item.title),
                  subtitle: switch (manifestEventMetadata(item)) {
                    final metadata when metadata.isNotEmpty => Text(
                      metadata.join(' · '),
                    ),
                    _ => null,
                  },
                  trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
                  onTap: () => onAction(item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotographyOpportunityAction extends StatelessWidget {
  const _PhotographyOpportunityAction({required this.opportunity});

  final PhotographyOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final startsIn = opportunity.startsAt.difference(now);
    final label = startsIn > const Duration(minutes: 1) ? '开始守候' : '查看拍摄判断';
    final time = TimeOfDay.fromDateTime(
      opportunity.startsAt.toLocal(),
    ).format(context);
    return Semantics(
      button: true,
      label: '$label，${opportunity.title}，$time 开始',
      child: InkWell(
        key: const Key('today-photography-opportunity'),
        onTap: () => context.go(
          Uri(
            path: '/shooting-window',
            queryParameters: {'opportunity': opportunity.id},
          ).toString(),
        ),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.timer_outlined,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$label · $time',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${opportunity.score}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionBar extends StatelessWidget {
  const _PrimaryActionBar({super.key, required this.item, required this.onTap});

  final ManifestItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary.withValues(alpha: .92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: .55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
          child: Row(
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 19,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '现在去做',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: .78,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.onPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlternateOpportunity extends StatelessWidget {
  const _AlternateOpportunity({required this.item, required this.onTap});

  final ManifestItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 17,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 17),
          ],
        ),
      ),
    ),
  );
}
