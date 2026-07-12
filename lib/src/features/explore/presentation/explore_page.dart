import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:x_amap_base/x_amap_base.dart';

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
            FilledButton(onPressed: onAccept, child: const Text('同意并开启地图')),
          ],
        ),
      ),
    );
  }
}

class _MapView extends ConsumerStatefulWidget {
  const _MapView({required this.mapBuilder, required this.onInit});

  final MapSurfaceBuilder? mapBuilder;
  final void Function(BuildContext context) onInit;

  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  @override
  void initState() {
    super.initState();
    widget.onInit(context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mapBuilder case final builder?) return builder();

    final locationConsent = ref.watch(environmentConsentProvider);
    if (!locationConsent) {
      return _LocationConsentView(
        onGrant: () => ref.read(environmentConsentProvider.notifier).grant(),
      );
    }

    final snapshot = ref.watch(environmentSnapshotProvider);
    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ExploreErrorView(
        onRetry: () => ref.read(environmentSnapshotProvider.notifier).refresh(),
      ),
      data: (value) {
        final location = value.location;
        if (location == null) {
          return _ExploreErrorView(
            onRetry: () =>
                ref.read(environmentSnapshotProvider.notifier).refresh(),
          );
        }
        final mapCenter = ChinaCoordinateConverter.wgs84ToGcj02(location);
        final places = ref.watch(nearbyPlacesProvider);
        return Stack(
          fit: StackFit.expand,
          children: [
            AMapWidget(
              initialCameraPosition: CameraPosition(
                target: LatLng(mapCenter.latitude, mapCenter.longitude),
                zoom: 13,
              ),
              compassEnabled: true,
              scaleEnabled: true,
              myLocationStyleOptions: MyLocationStyleOptions(true),
              markers:
                  places.asData?.value
                      .map(
                        (place) => Marker(
                          position: LatLng(
                            place.point.latitude,
                            place.point.longitude,
                          ),
                          infoWindow: InfoWindow(
                            title: place.name,
                            snippet: _distanceLabel(place.distanceMeters),
                          ),
                        ),
                      )
                      .toSet() ??
                  const <Marker>{},
            ),
            const Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: SafeArea(bottom: false, child: _CategoryBar()),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(top: false, child: _NearbyResultPanel(places)),
            ),
          ],
        );
      },
    );
  }

  static String _distanceLabel(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';
}

class _CategoryBar extends ConsumerWidget {
  const _CategoryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(nearbyCategoryProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final category in NearbyPlaceCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(category.label),
                  selected: category == selected,
                  onSelected: (_) => ref
                      .read(nearbyCategoryProvider.notifier)
                      .select(category),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NearbyResultPanel extends StatelessWidget {
  const _NearbyResultPanel(this.places);

  final AsyncValue<List<NearbyPlace>> places;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: places.when(
        loading: () => const SizedBox(
          height: 88,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) =>
            const SizedBox(height: 88, child: Center(child: Text('附近数据暂时不可用'))),
        data: (items) {
          if (items.isEmpty) {
            return const SizedBox(
              height: 88,
              child: Center(child: Text('这个范围内暂未找到相关地点')),
            );
          }
          return SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final place = items[index];
                return SizedBox(
                  width: 210,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    title: Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_MapViewState._distanceLabel(place.distanceMeters)}${place.address == null ? '' : ' · ${place.address}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.arrow_outward, size: 18),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _LocationConsentView extends StatelessWidget {
  const _LocationConsentView({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(LumaNestSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('从当前位置探索', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('允许后，栖光会加载附近机位、加油站和补给点。'),
          const Spacer(),
          FilledButton(onPressed: onGrant, child: const Text('同意并获取位置')),
        ],
      ),
    ),
  );
}

class _ExploreErrorView extends StatelessWidget {
  const _ExploreErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_outlined, size: 44),
          const SizedBox(height: 12),
          const Text('暂时无法获取当前位置'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}
