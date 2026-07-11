import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';

class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key, this.mapBuilder});

  final MapSurfaceBuilder? mapBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mapConsentControllerProvider);

    return switch (state) {
      MapConsentConfigurationMissing() => _ConfigurationMissingView(),
      MapConsentAwaiting() => _ConsentPrompt(
        onAccept: () {
          ref.read(mapConsentControllerProvider.notifier).grantConsent();
        },
      ),
      MapConsentReady() => _MapView(
        mapBuilder: mapBuilder,
        onInit: (context) {
          ref
              .read(mapConsentControllerProvider.notifier)
              .ensureInitialized(context);
        },
      ),
    };
  }
}

class _ConfigurationMissingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LumaNestSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.map_outlined, size: LumaNestSpacing.xl),
            const SizedBox(height: LumaNestSpacing.lg),
            Text('探索', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: LumaNestSpacing.sm),
            const Text('地图尚未配置'),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _ConsentPrompt extends StatelessWidget {
  const _ConsentPrompt({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LumaNestSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.map_outlined, size: LumaNestSpacing.xl),
            const SizedBox(height: LumaNestSpacing.lg),
            Text('探索', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: LumaNestSpacing.sm),
            const Text('开启地图前需要同意高德地图隐私政策。'),
            const Spacer(),
            FilledButton(
              onPressed: onAccept,
              child: const Text('同意并开启地图'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.mapBuilder, required this.onInit});

  final MapSurfaceBuilder? mapBuilder;
  final void Function(BuildContext context) onInit;

  @override
  Widget build(BuildContext context) {
    onInit(context);

    final builder = mapBuilder ?? (() => AMapWidget());
    return builder();
  }
}
