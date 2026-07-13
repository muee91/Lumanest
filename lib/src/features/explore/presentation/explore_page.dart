import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:x_amap_base/x_amap_base.dart';

class ExplorePage extends ConsumerWidget {
  const ExplorePage({
    super.key,
    this.mapBuilder,
    this.focus = ExploreFocus.photography,
  });

  final MapSurfaceBuilder? mapBuilder;
  final ExploreFocus focus;

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
        focus: focus,
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
  const _MapView({
    required this.mapBuilder,
    required this.focus,
    required this.onInit,
  });

  final MapSurfaceBuilder? mapBuilder;
  final ExploreFocus focus;
  final void Function(BuildContext context) onInit;

  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  @override
  void initState() {
    super.initState();
    widget.onInit(context);
    _applyFocus();
  }

  @override
  void didUpdateWidget(covariant _MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) _applyFocus();
  }

  void _applyFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(nearbyCategoryProvider.notifier).select(widget.focus.category);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mapBuilder case final builder?) {
      return Stack(
        fit: StackFit.expand,
        children: [
          builder(),
          if (widget.focus != ExploreFocus.photography)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: SafeArea(
                bottom: false,
                child: _FocusBanner(focus: widget.focus),
              ),
            ),
        ],
      );
    }

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
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    if (widget.focus != ExploreFocus.photography) ...[
                      _FocusBanner(focus: widget.focus),
                      const SizedBox(height: 8),
                    ],
                    const _CategoryBar(),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: _NearbyResultPanel(
                  places,
                  wildlifeActivity: value.wildlifeActivity,
                  focusWildlife: widget.focus == ExploreFocus.wildlife,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _distanceLabel(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';
}

class _FocusBanner extends StatelessWidget {
  const _FocusBanner({required this.focus});
  final ExploreFocus focus;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(focus.label, textAlign: TextAlign.center),
    ),
  );
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

class _NearbyResultPanel extends ConsumerWidget {
  const _NearbyResultPanel(
    this.places, {
    this.wildlifeActivity,
    this.focusWildlife = false,
  });

  final AsyncValue<List<NearbyPlace>> places;
  final RegionalWildlifeActivity? wildlifeActivity;
  final bool focusWildlife;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wildlifeActivity case final activity?) ...[
            _WildlifeActivitySummary(
              activity: activity,
              highlighted: focusWildlife,
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ],
          places.when(
            loading: () => const SizedBox(
              height: 88,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox(
              height: 88,
              child: Center(child: Text('附近数据暂时不可用')),
            ),
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: library?.containsPlace(place.id) == true
                                  ? '取消收藏'
                                  : '收藏',
                              onPressed: () => ref
                                  .read(userLibraryProvider.notifier)
                                  .togglePlace(
                                    SavedPlace(
                                      id: place.id,
                                      name: place.name,
                                      category: place.category.name,
                                      latitude: place.point.latitude,
                                      longitude: place.point.longitude,
                                    ),
                                  ),
                              icon: Icon(
                                library?.containsPlace(place.id) == true
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                              ),
                            ),
                            const Icon(Icons.arrow_outward, size: 18),
                          ],
                        ),
                        onTap: () async {
                          await ref
                              .read(userLibraryProvider.notifier)
                              .saveRecentRoute(
                                SavedRouteDestination(
                                  name: place.name,
                                  latitude: place.point.latitude,
                                  longitude: place.point.longitude,
                                ),
                              );
                          if (!context.mounted) return;
                          final target = Uri(
                            path: '/route',
                            queryParameters: {
                              'name': place.name,
                              'lat': '${place.point.latitude}',
                              'lon': '${place.point.longitude}',
                            },
                          );
                          context.go(target.toString());
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WildlifeActivitySummary extends StatelessWidget {
  const _WildlifeActivitySummary({
    required this.activity,
    required this.highlighted,
  });

  final RegionalWildlifeActivity activity;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final labels = activity.groups.map((group) => group.label).join(' · ');
    final hasMammals = activity.groups.contains(WildlifeGroup.mammal);
    final advice = hasMammals ? '仅在公共区域远观，不追逐、不投喂。' : '保持安静和距离，避免追逐、投喂或使用闪光灯。';
    return Semantics(
      container: true,
      label: '野外观察线索，GBIF 区域公开记录',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted
              ? Theme.of(context).colorScheme.tertiaryContainer
              : Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.pets_outlined, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '野外观察线索',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${activity.radiusKilometers} km 区域记录 · $labels',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(advice, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 3),
                    Text(
                      'GBIF 公开历史记录，不代表实时分布或风险。',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
