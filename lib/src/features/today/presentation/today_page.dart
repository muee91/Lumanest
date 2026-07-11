import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.snapshotAsync,
    this.onRetry,
  });

  final AsyncValue<ContextSnapshot> snapshotAsync;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return snapshotAsync.when(
      data: (snapshot) => _buildContent(context, snapshot),
      loading: () => _buildLoading(),
      error: (error, _) => _buildError(context, error),
    );
  }

  Widget _buildLoading() {
    return const SafeArea(
      child: Center(child: CircularProgressIndicator()),
    );
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
              Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(message, style: Theme.of(context).textTheme.bodyLarge),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('重试'),
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (snapshot.isStale)
            _StaleLabel(),
          Text('栖光', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('循光而行，择光而栖。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 28),
          Text(
            manifest.summary,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (manifest.safety.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SafetyRegion(items: manifest.safety),
          ],
          if (manifest.primary case final primary?) ...[
            const SizedBox(height: 20),
            _OpportunityCard(
              key: const Key('primary-opportunity'),
              item: primary,
            ),
          ],
          if (manifest.secondary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Column(
              key: const Key('secondary-opportunities'),
              children: [
                for (final item in manifest.secondary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _OpportunityCard(item: item, compact: true),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            manifest.inspirationPreview,
            key: const Key('inspiration-preview'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: () {}, child: const Text('探索附近')),
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
      return TodayPage(snapshotAsync: AsyncData(snapshot));
    }

    final granted = ref.watch(environmentConsentProvider);
    if (!granted) {
      return _EnvironmentConsentPrompt(
        onGrant: () => ref.read(environmentConsentProvider.notifier).grant(),
      );
    }

    final snapshot = ref.watch(environmentSnapshotProvider);
    return TodayPage(
      snapshotAsync: snapshot,
      onRetry: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
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
          Icon(Icons.access_time, size: 14, color: Theme.of(context).colorScheme.tertiary),
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
  const _SafetyRegion({required this.items});

  final List<ManifestItem> items;

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
              for (final item in items) Text(item.title),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({super.key, required this.item, this.compact = false});

  final ManifestItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            item.title,
            style: compact
                ? Theme.of(context).textTheme.bodyLarge
                : Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
    );
  }
}
