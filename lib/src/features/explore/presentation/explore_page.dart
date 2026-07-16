import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/environment_recovery.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/application/wildlife_map_layer_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/presentation/manual_location_sheet.dart';
import 'package:luma_nest/src/features/explore/presentation/wildlife_map_overlays.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_surface.dart';
import 'package:x_amap_base/x_amap_base.dart';

class ExplorePage extends ConsumerWidget {
  const ExplorePage({
    super.key,
    this.mapBuilder,
    this.focus = ExploreFocus.photography,
    this.intentTimeout = const Duration(minutes: 8),
    this.snapshotAsync,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
  });

  final MapSurfaceBuilder? mapBuilder;
  final ExploreFocus focus;
  final Duration intentTimeout;
  final AsyncValue<ContextSnapshot>? snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;

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
        snapshotAsync: snapshotAsync,
        onRetry: onRetry,
        onOpenAppSettings: onOpenAppSettings,
        onSelectManualLocation: onSelectManualLocation,
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
        padding: const EdgeInsets.all(LumaNestSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ExplorePageMark(),
            Expanded(
              child: Center(
                child: LumaNestSurface(
                  padding: const EdgeInsets.all(LumaNestSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 34,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: LumaNestSpacing.md),
                      Text(
                        '地图尚未配置',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: LumaNestSpacing.xs),
                      Text(
                        '完成高德地图配置后，附近机位、搜索与路线入口会在这里出现。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
        padding: const EdgeInsets.all(LumaNestSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ExplorePageMark(),
            Expanded(
              child: Center(
                child: LumaNestSurface(
                  padding: const EdgeInsets.all(LumaNestSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.layers_outlined,
                        size: 34,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: LumaNestSpacing.md),
                      Text(
                        '先确认地图隐私',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: LumaNestSpacing.xs),
                      Text(
                        '开启地图前需要同意高德地图隐私政策。栖光不会把你的精确位置历史保存到服务端。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: LumaNestSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onAccept,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('同意并开启地图'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorePageMark extends StatelessWidget {
  const _ExplorePageMark();

  @override
  Widget build(BuildContext context) => const LumaNestEyebrow(label: '探索');
}

class _MapView extends ConsumerStatefulWidget {
  const _MapView({
    required this.mapBuilder,
    required this.focus,
    required this.intentTimeout,
    this.snapshotAsync,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
    required this.onInit,
  });

  final MapSurfaceBuilder? mapBuilder;
  final ExploreFocus focus;
  final Duration intentTimeout;
  final AsyncValue<ContextSnapshot>? snapshotAsync;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;
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
  GeoPoint? _searchCenter;
  bool _mapInitialized = false;
  bool _searchFocused = false;
  int _searchRevision = 0;
  SceneType? _requestedScene;

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
          .search(query, center: _searchCenter);
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
    final locationDisplay = ref.watch(environmentLocationDisplayProvider);
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
                  if (locationDisplay.isReference) ...[
                    const SizedBox(height: 8),
                    _ReferenceLocationBanner(locationDisplay),
                  ],
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

    final AsyncValue<ContextSnapshot> snapshot =
        widget.snapshotAsync ?? ref.watch(environmentSnapshotProvider)!;
    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ExploreErrorView(
        error: error,
        onRetry:
            widget.onRetry ??
            (widget.snapshotAsync == null
                ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
                : null),
        onOpenAppSettings:
            widget.onOpenAppSettings ??
            (widget.snapshotAsync == null ? Geolocator.openAppSettings : null),
        onSelectManualLocation:
            widget.onSelectManualLocation ??
            (widget.snapshotAsync == null
                ? () => _showManualLocation(context)
                : null),
      ),
      data: (value) {
        _syncSceneLayer(value.primaryScene);
        final location = value.location;
        if (location == null) {
          return _ExploreErrorView(
            error: null,
            onRetry:
                widget.onRetry ??
                (widget.snapshotAsync == null
                    ? () => ref
                          .read(environmentSnapshotProvider.notifier)
                          .refresh()
                    : null),
            onSelectManualLocation:
                widget.onSelectManualLocation ??
                (widget.snapshotAsync == null
                    ? () => _showManualLocation(context)
                    : null),
          );
        }
        _searchCenter = location;
        final mapCenter = ChinaCoordinateConverter.wgs84ToGcj02(location);
        final places = ref.watch(nearbyPlacesProvider);
        final AsyncValue<WildlifeMapLayer>? wildlifeLayer =
            activeFocus == ExploreFocus.wildlife
            ? ref.watch(
                wildlifeMapLayerProvider((
                  latitude: location.latitude,
                  longitude: location.longitude,
                  radiusKilometers: 20,
                )),
              )
            : null;
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
              myLocationStyleOptions: MyLocationStyleOptions(
                !locationDisplay.isReference,
              ),
              markers: _buildMarkers(places),
              polygons: buildWildlifeMapPolygons(wildlifeLayer?.asData?.value),
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
                    if (locationDisplay.isReference) ...[
                      const SizedBox(height: 8),
                      _ReferenceLocationBanner(locationDisplay),
                    ],
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
                        wildlifeLayer: wildlifeLayer,
                        focusWildlife: activeFocus == ExploreFocus.wildlife,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _syncSceneLayer(SceneType scene) {
    if (_requestedScene == scene) return;
    _requestedScene = scene;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _requestedScene != scene) return;
      ref.read(exploreIntentProvider.notifier).syncScene(scene);
    });
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

  Future<void> _showManualLocation(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const ManualLocationSheet(),
      );
}

class _FocusBanner extends StatelessWidget {
  const _FocusBanner({required this.focus});
  final ExploreFocus focus;

  @override
  Widget build(BuildContext context) => LumaNestSurface(
    tone: LumaNestSurfaceTone.mapOverlay,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.filter_center_focus_rounded,
          size: 17,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            focus.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    ),
  );
}

class _ReferenceLocationBanner extends StatelessWidget {
  const _ReferenceLocationBanner(this.location);

  final EnvironmentLocationDisplay location;

  @override
  Widget build(BuildContext context) => LumaNestSurface(
    tone: LumaNestSurfaceTone.mapOverlay,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.location_on_outlined,
          size: 17,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            location.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    ),
  );
}

class _CategoryBar extends ConsumerWidget {
  const _CategoryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(nearbyCategoryProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .84),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .72),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
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
    this.wildlifeLayer,
    this.focusWildlife = false,
  });

  final AsyncValue<List<NearbyPlace>> places;
  final RegionalWildlifeActivity? wildlifeActivity;
  final AsyncValue<WildlifeMapLayer>? wildlifeLayer;
  final bool focusWildlife;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    final category = ref.watch(nearbyCategoryProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .74),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              children: [
                Icon(
                  Icons.near_me_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Text(
                  '附近${category.label}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '点击地点规划路线',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
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
          if (focusWildlife)
            if (wildlifeLayer case final layer?) ...[
              _WildlifeLayerStatus(layer),
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
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final place = items[index];
                    return SizedBox(
                      width: 224,
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: .65),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
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
                                tooltip:
                                    library?.containsPlace(place.id) == true
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
                              const Icon(Icons.arrow_forward_rounded, size: 18),
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
    final concentration = activity.historicalRecordConcentration?.summary;
    final datasetAttribution = activity.datasets
        .take(2)
        .map((dataset) {
          final licenses = dataset.licenses.join('/');
          return '${dataset.publisher}《${dataset.title}》${licenses.isEmpty ? '' : '（$licenses）'}';
        })
        .join('；');
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
                      '${activity.radiusKilometers} km 区域记录 · ${activity.occurrenceSampleSize} 条可追溯采样 · $labels',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (concentration != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '历史记录集中：$concentration（仅反映公开记录采样，不代表活动规律）',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(advice, style: Theme.of(context).textTheme.bodySmall),
                    if (datasetAttribution.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '数据署名：$datasetAttribution${activity.datasets.length > 2 ? '等 ${activity.datasets.length} 个数据集' : ''}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
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

class _WildlifeLayerStatus extends StatelessWidget {
  const _WildlifeLayerStatus(this.layer);

  final AsyncValue<WildlifeMapLayer> layer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.layers_outlined, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: layer.when(
            loading: () => const Text('正在读取已审核历史观察区域'),
            error: (_, _) => const Text('审核区域图层暂不可用；GBIF 区域摘要仍可参考'),
            data: (value) {
              if (value.areas.isEmpty) {
                return Text(
                  '${value.isOfflineCache ? '离线缓存 · ' : ''}'
                  '附近暂无已审核的历史观察区域图层',
                );
              }
              final sources = value.attributions.take(2).join(' · ');
              return Text(
                '已覆盖 ${value.areas.length} 个审核区域 · '
                '${value.isOfflineCache ? '离线缓存 · ' : ''}'
                '非实时位置 · $sources',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
      ],
    ),
  );
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
  const _ExploreErrorView({
    required this.error,
    this.onRetry,
    this.onOpenAppSettings,
    this.onSelectManualLocation,
  });

  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenAppSettings;
  final VoidCallback? onSelectManualLocation;

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied = switch (error) {
      final value? => isPermanentlyDeniedLocationFailure(value),
      null => false,
    };
    final primaryAction = permanentlyDenied
        ? onOpenAppSettings ?? onRetry
        : onRetry;
    final primaryLabel = permanentlyDenied && onOpenAppSettings != null
        ? '打开设置'
        : '重试';
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 44),
            const SizedBox(height: 12),
            const Text('暂时无法获取当前位置'),
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
        ),
      ),
    );
  }
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
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(24),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索地点',
                  prefixIcon: const Icon(Icons.search_rounded),
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
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                ),
              ),
            )
          : GestureDetector(
              onTap: onExpand,
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .96),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: .16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .72),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Text('搜索地点'),
                      const Spacer(),
                      Text(
                        '地点 / 机位 / 补给',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
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
    final locationPrioritized =
        results.asData?.value.any((item) => item.distanceMeters != null) ==
        true;
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .74),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  locationPrioritized ? '搜索结果 · 附近优先' : '搜索结果',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return SizedBox(
                      width: 224,
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: .65),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
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
                          trailing: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          onTap: () => onSelect(item),
                        ),
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
    if (item.distanceMeters case final distance?)
      distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} km'
          : '$distance m',
    if (item.address case final address? when address.isNotEmpty) address,
    if (item.isOfflineCache) '离线缓存',
  ].join(' · ');
}
