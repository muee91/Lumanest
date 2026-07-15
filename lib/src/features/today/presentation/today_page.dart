import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/environment_recovery.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.snapshotAsync,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
    this.onManifestAction,
    this.narrativeAsync,
    this.manifest,
  });

  final AsyncValue<ContextSnapshot> snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;
  final ValueChanged<ManifestItem>? onManifestAction;
  final AsyncValue<ManifestNarrative>? narrativeAsync;
  final UiManifest? manifest;

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
    final summary =
        narrativeAsync?.asData?.value.summary ?? effectiveManifest.summary;
    void performAction(ManifestItem item) {
      final injected = onManifestAction;
      if (injected != null) {
        injected(item);
      } else {
        handleManifestAction(context, item);
      }
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          LumaNestSpacing.md,
          LumaNestSpacing.md,
          LumaNestSpacing.md,
          LumaNestSpacing.xl,
        ),
        children: [
          if (snapshot.isStale) _StaleLabel(),
          _TodayMasthead(snapshot: snapshot),
          const SizedBox(height: LumaNestSpacing.lg),
          _DecisionHero(summary: summary, dayPhase: snapshot.dayPhase),
          const SizedBox(height: LumaNestSpacing.md),
          _EnvironmentStrip(snapshot: snapshot),
          const SizedBox(height: LumaNestSpacing.lg),
          if (effectiveManifest.safety.isNotEmpty) ...[
            _SafetyRegion(
              items: effectiveManifest.safety,
              onAction: performAction,
            ),
            const SizedBox(height: LumaNestSpacing.lg),
          ],
          if (effectiveManifest.primary case final primary?) ...[
            _OpportunityCard(
              key: const Key('primary-opportunity'),
              item: primary,
              onTap: () => performAction(primary),
            ),
            const SizedBox(height: LumaNestSpacing.sm),
          ],
          if (effectiveManifest.secondary.isNotEmpty) ...[
            const SizedBox(height: LumaNestSpacing.sm),
            Column(
              key: const Key('secondary-opportunities'),
              children: [
                for (final item in effectiveManifest.secondary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LumaNestSpacing.xs),
                    child: _OpportunityCard(
                      item: item,
                      compact: true,
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
          const SizedBox(height: LumaNestSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/explore'),
              icon: const Icon(Icons.explore_outlined),
              label: const Text('探索附近'),
            ),
          ),
        ],
      ),
    );
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
  const _TodayMasthead({required this.snapshot});
  final ContextSnapshot snapshot;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: .28),
                    blurRadius: 12,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LumaNestSpacing.sm),
            Expanded(child: Text('栖光', style: theme.textTheme.displaySmall)),
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
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Text(scene, style: theme.textTheme.labelLarge),
              ),
            ),
          ],
        ),
        const SizedBox(height: LumaNestSpacing.xxs),
        Padding(
          padding: const EdgeInsets.only(left: 23),
          child: Text(
            '循光而行，择光而栖。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: .8,
            ),
          ),
        ),
      ],
    );
  }
}

class _DecisionHero extends StatelessWidget {
  const _DecisionHero({required this.summary, required this.dayPhase});
  final String summary;
  final DayPhase dayPhase;

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
    return Semantics(
      container: true,
      label: '$label，$summary',
      child: Container(
        constraints: const BoxConstraints(minHeight: 190),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: .94),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: .88),
            ],
          ),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: .2),
          ),
          borderRadius: BorderRadius.circular(32),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -48,
              top: -58,
              child: Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: .13),
                    width: 26,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(LumaNestSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.north_east_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: LumaNestSpacing.xl),
                  Text(summary, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: LumaNestSpacing.md),
                  Text(
                    '基于此刻环境与有效事件',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentStrip extends StatelessWidget {
  const _EnvironmentStrip({required this.snapshot});
  final ContextSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String, String)>[
      if (snapshot.temperatureCelsius case final value?)
        (Icons.device_thermostat_outlined, '${value.round()}°', '气温'),
      if (snapshot.windSpeedMetersPerSecond case final value?)
        (Icons.air_outlined, '${value.toStringAsFixed(1)} m/s', '风速'),
      if (snapshot.visibilityKilometers case final value?)
        (Icons.visibility_outlined, '${value.round()} km', '能见度'),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .86),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .7),
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
        child: Column(
          children: [
            Row(
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
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: .7,
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: LumaNestSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '天气数据：和风天气',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => Material(
    color: Theme.of(
      context,
    ).colorScheme.secondaryContainer.withValues(alpha: .7),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: .22),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
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
      ),
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
      onRetry: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
      onOpenAppSettings: Geolocator.openAppSettings,
      onSelectManualLocation: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const ManualLocationSheet(),
      ),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    super.key,
    required this.item,
    required this.onTap,
    this.compact = false,
  });

  final ManifestItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: compact
          ? theme.colorScheme.surfaceContainerLow.withValues(alpha: .86)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        side: BorderSide(
          color: compact
              ? theme.colorScheme.outlineVariant.withValues(alpha: .72)
              : theme.colorScheme.primary.withValues(alpha: .34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 20),
          child: Row(
            children: [
              if (!compact) ...[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    size: 19,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      compact ? '备选线索' : '此刻主行动',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      style: compact
                          ? theme.textTheme.bodyLarge
                          : theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
