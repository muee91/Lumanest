import 'dart:async';

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
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:x_amap_base/x_amap_base.dart';

class ExplorePage extends ConsumerWidget {
  const ExplorePage({
    super.key,
    this.mapBuilder,
    this.focus = ExploreFocus.photography,
    this.intentTimeout = const Duration(minutes: 8),
  });

  final MapSurfaceBuilder? mapBuilder;
  final ExploreFocus focus;
  final Duration intentTimeout;

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
        intentTimeout: intentTimeout,
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
    required this.intentTimeout,
    required this.onInit,
  });

  final MapSurfaceBuilder? mapBuilder;
  final ExploreFocus focus;
  final Duration intentTimeout;
  final void Function(BuildContext context) onInit;

  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  Timer? _intentTimer;
  AsyncValue<List<LocationSearchResult>>? _searchResults;
  bool _mapInitialized = false;
  bool _searchFocused = false;
  int _searchRevision = 0;

  @override
  void initState() {
    super.initState();
    _applyRequestedFocus();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mapInitialized) return;
    _mapInitialized = true;
    widget.onInit(context);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _intentTimer?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    final focused = _searchFocusNode.hasFocus;
    if (focused != _searchFocused) {
      setState(() => _searchFocused = focused);
    }
  }

  void _expandSearch() {
    if (!_searchFocused) setState(() => _searchFocused = true);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    final revision = ++_searchRevision;
    _debounce?.cancel();
    _debounce = null;
    if (query.isEmpty) {
      if (_searchResults != null) setState(() => _searchResults = null);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _performSearch(query, revision),
    );
  }

  Future<void> _performSearch(String query, int revision) async {
    if (!mounted || revision != _searchRevision) return;
    setState(() => _searchResults = const AsyncLoading());
    try {
      final results = await ref
          .read(locationSearchRepositoryProvider)
          .search(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() => _searchResults = AsyncData(results));
    } on Object catch (e, st) {
      if (!mounted || revision != _searchRevision) return;
      setState(() => _searchResults = AsyncError(e, st));
    }
  }

  Future<void> _onSearchResultSelected(LocationSearchResult result) async {
    var persisted = true;
    try {
      await ref
          .read(userLibraryProvider.notifier)
          .saveRecentRoute(
            SavedRouteDestination(
              name: result.name,
              latitude: result.point.latitude,
              longitude: result.point.longitude,
            ),
          );
    } on Object {
      persisted = false;
    }
    if (!mounted) return;
    ref
        .read(exploreIntentProvider.notifier)
        .complete(category: ref.read(nearbyCategoryProvider));
    if (!persisted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('路线可以继续使用，但未能保存到最近路线')));
    }
    context.go(
      Uri(
        path: '/route',
        queryParameters: {
          'name': result.name,
          'lat': '${result.point.latitude}',
          'lon': '${result.point.longitude}',
        },
      ).toString(),
    );
  }

  @override
  void didUpdateWidget(covariant _MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) _applyRequestedFocus();
  }

  void _applyRequestedFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(exploreIntentProvider.notifier).activate(widget.focus);
      _intentTimer?.cancel();
      if (widget.focus == ExploreFocus.photography) return;
      _intentTimer = Timer(widget.intentTimeout, _expireIntent);
    });
  }

  void _expireIntent() {
    if (!mounted) return;
    final expired = ref.read(exploreIntentProvider.notifier).expire();
    if (expired) GoRouter.maybeOf(context)?.go('/explore');
  }

  @override
  Widget build(BuildContext context) {
    final activeFocus = ref.watch(exploreIntentProvider).activeFocus;
    if (widget.mapBuilder case final builder?) {
      return Stack(
        fit: StackFit.expand,
        children: [
          builder(),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _SearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    expanded: _searchFocused,
                    onExpand: _expandSearch,
                  ),
                  if (activeFocus case final focus?) ...[
                    const SizedBox(height: 8),
                    _FocusBanner(focus: focus),
                  ],
                  const SizedBox(height: 8),
                  const _CategoryBar(),
                ],
              ),
            ),
          ),
          if (_searchResults != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: _SearchResultPanel(
                  _searchResults!,
                  onSelect: _onSearchResultSelected,
                ),
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
              markers: _buildMarkers(places),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      expanded: _searchFocused,
                      onExpand: _expandSearch,
                    ),
                    const SizedBox(height: 8),
                    if (activeFocus case final focus?) ...[
                      _FocusBanner(focus: focus),
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
                child: _searchResults != null
                    ? _SearchResultPanel(
                        _searchResults!,
                        onSelect: _onSearchResultSelected,
                      )
                    : _NearbyResultPanel(
                        places,
                        wildlifeActivity: value.wildlifeActivity,
                        focusWildlife: activeFocus == ExploreFocus.wildlife,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Set<Marker> _buildMarkers(AsyncValue<List<NearbyPlace>> places) {
    if (_searchResults?.asData?.value case final results?) {
      return results
          .map(
            (result) => Marker(
              position: LatLng(result.point.latitude, result.point.longitude),
              infoWindow: InfoWindow(title: result.name),
            ),
          )
          .toSet();
    }
    return places.asData?.value
            .map(
              (place) => Marker(
                position: LatLng(place.point.latitude, place.point.longitude),
                infoWindow: InfoWindow(
                  title: place.name,
                  snippet: _distanceLabel(place.distanceMeters),
                ),
              ),
            )
            .toSet() ??
        const <Marker>{};
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
                  onSelected: (_) {
                    ref
                        .read(exploreIntentProvider.notifier)
                        .complete(category: category);
                    GoRouter.maybeOf(context)?.go('/explore');
                  },
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
                          _metadata(place),
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
                          ref
                              .read(exploreIntentProvider.notifier)
                              .complete(
                                category: ref.read(nearbyCategoryProvider),
                              );
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

  static String _metadata(NearbyPlace place) => [
    _MapViewState._distanceLabel(place.distanceMeters),
    if (place.address case final address? when address.isNotEmpty) address,
    if (place.isOfflineCache) '离线缓存',
  ].join(' · ');
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.expanded,
    required this.onExpand,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool expanded;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: expanded
          ? Material(
              color: Colors.transparent,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索地点',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => controller.clear(),
                          ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: .92),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            )
          : GestureDetector(
              onTap: onExpand,
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(18),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search),
                      SizedBox(width: 8),
                      Text('搜索地点'),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SearchResultPanel extends StatelessWidget {
  const _SearchResultPanel(this.results, {required this.onSelect});

  final AsyncValue<List<LocationSearchResult>> results;
  final ValueChanged<LocationSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18),
                const SizedBox(width: 8),
                Text('搜索结果', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          results.when(
            loading: () => const SizedBox(
              height: 88,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox(
              height: 88,
              child: Center(child: Text('搜索暂时不可用')),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox(
                  height: 88,
                  child: Center(child: Text('未找到相关地点')),
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
                    final item = items[index];
                    return SizedBox(
                      width: 210,
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _metadata(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_outward, size: 18),
                        onTap: () => onSelect(item),
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

  static String _metadata(LocationSearchResult item) => [
    if (item.address case final address? when address.isNotEmpty) address,
    if (item.isOfflineCache) '离线缓存',
  ].join(' · ');
}
