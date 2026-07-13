import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.snapshotAsync,
    this.onRetry,
    this.onSelectManualLocation,
    this.onManifestAction,
    this.narrativeAsync,
  });

  final AsyncValue<ContextSnapshot> snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onSelectManualLocation;
  final ValueChanged<ManifestItem>? onManifestAction;
  final AsyncValue<ManifestNarrative>? narrativeAsync;

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
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
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
    final manifest = ManifestPolicy.build(snapshot);
    final summary = narrativeAsync?.asData?.value.summary ?? manifest.summary;
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          if (snapshot.isStale) _StaleLabel(),
          _TodayMasthead(snapshot: snapshot),
          const SizedBox(height: 28),
          _DecisionHero(summary: summary, dayPhase: snapshot.dayPhase),
          const SizedBox(height: 16),
          _EnvironmentStrip(snapshot: snapshot),
          const SizedBox(height: 20),
          if (manifest.safety.isNotEmpty) ...[
            _SafetyRegion(items: manifest.safety, onAction: performAction),
            const SizedBox(height: 20),
          ],
          if (manifest.primary case final primary?) ...[
            _OpportunityCard(
              key: const Key('primary-opportunity'),
              item: primary,
              onTap: () => performAction(primary),
            ),
            const SizedBox(height: 12),
          ],
          if (manifest.secondary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Column(
              key: const Key('secondary-opportunities'),
              children: [
                for (final item in manifest.secondary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _OpportunityCard(
                      item: item,
                      compact: true,
                      onTap: () => performAction(item),
                    ),
                  ),
              ],
            ),
          ],
          if (manifest.inspirationPreview.isNotEmpty) ...[
            const SizedBox(height: 18),
            _InspirationTeaser(
              note: manifest.inspirationPreview,
              onTap: () => context.go('/inspiration'),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => context.go('/explore'),
            icon: const Icon(Icons.explore_outlined),
            label: const Text('探索附近'),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('栖光', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 3),
              Text('循光而行，择光而栖。', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(scene, style: Theme.of(context).textTheme.labelLarge),
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
    final label = switch (dayPhase) {
      DayPhase.dawn => '晨光判断',
      DayPhase.day => '今日判断',
      DayPhase.sunset => '落日判断',
      DayPhase.blueHour => '蓝调判断',
      DayPhase.night => '夜间判断',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Text(summary, style: Theme.of(context).textTheme.headlineSmall),
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
    final entries = <(IconData, String)>[
      (
        Icons.device_thermostat_outlined,
        snapshot.temperatureCelsius == null
            ? '温度 --'
            : '${snapshot.temperatureCelsius!.round()}°',
      ),
      (
        Icons.air_outlined,
        snapshot.windSpeedMetersPerSecond == null
            ? '风力 --'
            : '${snapshot.windSpeedMetersPerSecond!.toStringAsFixed(1)} m/s',
      ),
      (
        Icons.visibility_outlined,
        snapshot.visibilityKilometers == null
            ? '能见度 --'
            : '${snapshot.visibilityKilometers!.round()} km',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            for (final entry in entries)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: entry == entries.last ? 0 : 8,
                  ),
                  child: _MetricPill(icon: entry.$1, label: entry.$2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '天气数据：和风天气',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainer.withValues(alpha: .8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
}

class _InspirationTeaser extends StatelessWidget {
  const _InspirationTeaser({required this.note, required this.onTap});
  final String note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note,
                key: const Key('inspiration-preview'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Icon(Icons.arrow_outward, size: 18),
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
      narrativeAsync: narrative,
      onRetry: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
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
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('安全提醒', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(item.title),
                  trailing: const Icon(Icons.chevron_right),
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: compact
                      ? Theme.of(context).textTheme.bodyLarge
                      : Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Icon(Icons.arrow_outward, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
