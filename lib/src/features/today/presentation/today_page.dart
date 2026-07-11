import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.manifest});

  final UiManifest manifest;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
