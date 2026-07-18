import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:x_amap_base/x_amap_base.dart';

class V2ExplorePage extends ConsumerWidget {
  const V2ExplorePage({super.key, this.focus = ExploreFocus.photography});

  final ExploreFocus focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(environmentConsentProvider)) {
      return V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.location,
          title: '地图从你所在之处展开',
          detail: '位置只用于当前地图与附近查询，不形成服务端轨迹。',
          action: '允许位置',
          onAction: () => ref.read(environmentConsentProvider.notifier).grant(),
        ),
      );
    }
    return switch (ref.watch(mapConsentControllerProvider)) {
      MapConsentConfigurationMissing() => V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.map,
          title: '地图尚未配置',
          detail: 'Android 地图密钥缺失，附近地点与路线暂不可用。',
          action: '回到今日',
          onAction: () => context.go('/today'),
        ),
      ),
      MapConsentAwaiting() => V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.hand_raised,
          title: '先确认地图隐私',
          detail: '开启地图前需要同意高德地图隐私政策，精确位置历史不会保存到服务端。',
          action: '同意并开启地图',
          onAction: () =>
              ref.read(mapConsentControllerProvider.notifier).grantConsent(),
        ),
      ),
      MapConsentReady() => _V2ExploreMap(focus: focus),
    };
  }
}

class _V2ExploreMap extends ConsumerStatefulWidget {
  const _V2ExploreMap({required this.focus});
  final ExploreFocus focus;

  @override
  ConsumerState<_V2ExploreMap> createState() => _V2ExploreMapState();
}

class _V2ExploreMapState extends ConsumerState<_V2ExploreMap> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  AMapController? _mapController;
  AsyncValue<List<LocationSearchResult>>? _searchResults;
  NearbyPlace? _selectedPlace;
  LocationSearchResult? _selectedSearchResult;
  double _panelFraction = .12;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(exploreIntentProvider.notifier).activate(widget.focus);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _tryInitializeMap();
  }

  void _tryInitializeMap() {
    final consent = ref.read(mapConsentControllerProvider);
    if (consent is! MapConsentReady) return;
    ref.read(mapConsentControllerProvider.notifier).ensureInitialized(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController?.disponse();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      if (!mounted) return;
      setState(() {
        _searchResults = const AsyncLoading();
        _panelFraction = .5;
      });
      try {
        final snapshot = await ref.read(environmentSnapshotProvider.future);
        final result = await ref
            .read(locationSearchRepositoryProvider)
            .search(query, center: snapshot.location);
        if (mounted) setState(() => _searchResults = AsyncData(result));
      } on Object catch (error, stack) {
        if (mounted) setState(() => _searchResults = AsyncError(error, stack));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(environmentSnapshotProvider);
    return snapshot.when(
      loading: () => const ColoredBox(
        color: V2Palette.canvas,
        child: V2LoadingObject(label: '正在展开附近地图'),
      ),
      error: (_, _) => V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.location_slash,
          title: '地图暂时找不到起点',
          detail: '更新位置后再探索附近。',
          action: '重新获取',
          onAction: () =>
              ref.read(environmentSnapshotProvider.notifier).refresh(),
        ),
      ),
      data: _buildMap,
    );
  }

  Widget _buildMap(ContextSnapshot snapshot) {
    final origin = snapshot.location;
    if (origin == null) {
      return V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.location_slash,
          title: '没有可用起点',
          detail: '选择一个参考地点后再打开地图。',
          action: '回到今日',
          onAction: () => context.go('/today'),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(nearbySearchAreaProvider.notifier).syncBase(origin);
        ref
            .read(exploreIntentProvider.notifier)
            .syncScene(snapshot.primaryScene);
      }
    });
    final places = ref.watch(nearbyPlacesProvider);
    final intent = ref.watch(exploreIntentProvider);
    final mapCenter = ChinaCoordinateConverter.wgs84ToGcj02(origin);
    final markers = _markers(places);

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelHeight = constraints.maxHeight * _panelFraction;
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        final bottomPadding = MediaQuery.paddingOf(context).bottom;
        return Stack(
          fit: StackFit.expand,
          children: [
            AMapWidget(
              initialCameraPosition: CameraPosition(
                target: LatLng(mapCenter.latitude, mapCenter.longitude),
                zoom: 13,
              ),
              onMapCreated: (controller) => _mapController = controller,
              myLocationStyleOptions: MyLocationStyleOptions(true),
              compassEnabled: false,
              scaleEnabled: false,
              markers: markers,
              onCameraMoveEnd: (position) {
                final gcj = GeoPoint(
                  latitude: position.target.latitude,
                  longitude: position.target.longitude,
                  coordinateSystem: CoordinateSystem.gcj02,
                );
                ref
                    .read(nearbySearchAreaProvider.notifier)
                    .markMapMoved(ChinaCoordinateConverter.gcj02ToWgs84(gcj));
              },
            ),
            Positioned(
              left: 18,
              right: 18,
              top: MediaQuery.paddingOf(context).top + 12,
              child: _V2SearchObject(
                controller: _searchController,
                focusNode: _searchFocus,
                onClear: () {
                  _searchController.clear();
                  _searchFocus.unfocus();
                },
              ),
            ),
            Positioned(
              left: 18,
              top: MediaQuery.paddingOf(context).top + 82,
              child: _V2IntentObject(
                intent: intent.creativeIntent,
                category: intent.category,
                onNext: () {
                  final values = ExploreCreativeIntent.values;
                  final current = intent.creativeIntent;
                  final next = current == null
                      ? values.first
                      : values[(values.indexOf(current) + 1) % values.length];
                  ref
                      .read(exploreIntentProvider.notifier)
                      .chooseCreativeIntent(next);
                },
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: 12,
              right: 12,
              bottom: bottomInset + bottomPadding + 80,
              height: panelHeight.clamp(
                92,
                (constraints.maxHeight - bottomInset) * .68,
              ),
              child: _V2ExploreResultObject(
                places: places,
                searchResults: _searchResults,
                selectedPlace: _selectedPlace,
                selectedSearchResult: _selectedSearchResult,
                expanded: _panelFraction > .3,
                onDrag: (delta) => setState(() {
                  _panelFraction =
                      (_panelFraction - delta / constraints.maxHeight).clamp(
                        .12,
                        .68,
                      );
                }),
                onSnap: () => setState(() {
                  _panelFraction = _panelFraction > .34 ? .68 : .12;
                }),
                onPlace: _selectPlace,
                onSearchResult: _selectSearchResult,
                onRoute: _openRoute,
                onSave: _toggleSave,
                onSearchMapArea: () => ref
                    .read(nearbySearchAreaProvider.notifier)
                    .searchPendingArea(),
              ),
            ),
          ],
        );
      },
    );
  }

  Set<Marker> _markers(AsyncValue<List<NearbyPlace>> places) {
    final result = <Marker>{};
    for (final place in places.asData?.value ?? const <NearbyPlace>[]) {
      final point = ChinaCoordinateConverter.wgs84ToGcj02(place.point);
      result.add(
        Marker(
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(title: place.name),
          onTap: (_) => _selectPlace(place),
          zIndex: _selectedPlace?.id == place.id ? 2 : 1,
        ),
      );
    }
    for (final item
        in _searchResults?.asData?.value ?? const <LocationSearchResult>[]) {
      final point = ChinaCoordinateConverter.wgs84ToGcj02(item.point);
      result.add(
        Marker(
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(title: item.name),
          onTap: (_) => _selectSearchResult(item),
          zIndex: _selectedSearchResult?.id == item.id ? 3 : 1,
        ),
      );
    }
    return result;
  }

  void _selectPlace(NearbyPlace place) {
    _searchFocus.unfocus();
    setState(() {
      _selectedPlace = place;
      _selectedSearchResult = null;
      _panelFraction = .5;
    });
    _focusPoint(place.point);
  }

  void _selectSearchResult(LocationSearchResult item) {
    _searchFocus.unfocus();
    setState(() {
      _selectedSearchResult = item;
      _selectedPlace = null;
      _panelFraction = .5;
    });
    _focusPoint(item.point);
  }

  void _focusPoint(GeoPoint point) {
    final gcj = ChinaCoordinateConverter.wgs84ToGcj02(point);
    unawaited(
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(gcj.latitude, gcj.longitude), zoom: 15),
        ),
        duration: 520,
      ),
    );
  }

  void _openRoute(String name, GeoPoint point) {
    context.go(
      '/route?name=${Uri.encodeQueryComponent(name)}'
      '&lat=${point.latitude}&lon=${point.longitude}',
    );
  }

  void _toggleSave(NearbyPlace place) {
    ref
        .read(userLibraryProvider.notifier)
        .togglePlace(
          SavedPlace(
            id: place.id,
            name: place.name,
            category: place.category.name,
            latitude: place.point.latitude,
            longitude: place.point.longitude,
          ),
        );
  }
}

class _V2SearchObject extends StatelessWidget {
  const _V2SearchObject({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: V2Palette.paper,
    elevation: 10,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(24),
    child: TextField(
      key: const Key('v2-explore-search'),
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: '搜索地点',
        prefixIcon: const Icon(CupertinoIcons.search, color: V2Palette.ink),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(CupertinoIcons.xmark_circle_fill),
              ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
      ),
    ),
  );
}

class _V2IntentObject extends StatelessWidget {
  const _V2IntentObject({
    required this.intent,
    required this.category,
    required this.onNext,
  });
  final ExploreCreativeIntent? intent;
  final NearbyPlaceCategory category;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onNext,
    compact: true,
    color: V2Palette.night,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.scope, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          Text(
            intent?.label ?? '找${category.label}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _V2ExploreResultObject extends ConsumerWidget {
  const _V2ExploreResultObject({
    required this.places,
    required this.searchResults,
    required this.selectedPlace,
    required this.selectedSearchResult,
    required this.expanded,
    required this.onDrag,
    required this.onSnap,
    required this.onPlace,
    required this.onSearchResult,
    required this.onRoute,
    required this.onSave,
    required this.onSearchMapArea,
  });
  final AsyncValue<List<NearbyPlace>> places;
  final AsyncValue<List<LocationSearchResult>>? searchResults;
  final NearbyPlace? selectedPlace;
  final LocationSearchResult? selectedSearchResult;
  final bool expanded;
  final ValueChanged<double> onDrag;
  final VoidCallback onSnap;
  final ValueChanged<NearbyPlace> onPlace;
  final ValueChanged<LocationSearchResult> onSearchResult;
  final void Function(String, GeoPoint) onRoute;
  final ValueChanged<NearbyPlace> onSave;
  final VoidCallback onSearchMapArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    return Material(
      color: V2Palette.paper,
      elevation: 16,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(32),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSnap,
            onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
            onVerticalDragEnd: (_) => onSnap(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 11, 20, 8),
              child: Column(
                children: [
                  const V2GrabHandle(),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedPlace?.name ??
                              selectedSearchResult?.name ??
                              (searchResults == null ? '附近正在发生' : '搜索结果'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: V2Palette.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.4,
                          ),
                        ),
                      ),
                      Text(
                        expanded ? '收起' : '向上探索',
                        style: const TextStyle(
                          color: V2Palette.moss,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) Expanded(child: _body(context, library)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, UserLibraryState? library) {
    final selected = selectedPlace;
    if (selected != null) {
      return _V2SelectedPlace(
        name: selected.name,
        detail: _placeDetail(selected),
        saved: library?.containsPlace(selected.id) == true,
        onSave: () => onSave(selected),
        onRoute: () => onRoute(selected.name, selected.point),
      );
    }
    final searched = selectedSearchResult;
    if (searched != null) {
      return _V2SelectedPlace(
        name: searched.name,
        detail: [
          if (searched.address?.isNotEmpty == true) searched.address!,
          if (searched.distanceMeters != null)
            _distance(searched.distanceMeters!),
        ].join(' · '),
        onRoute: () => onRoute(searched.name, searched.point),
      );
    }
    final search = searchResults;
    if (search != null) {
      return search.when(
        loading: () => const V2LoadingObject(label: '正在寻找地点'),
        error: (_, _) => const Center(child: Text('搜索暂时不可用')),
        data: (items) => _V2ResultList<LocationSearchResult>(
          items: items,
          title: (item) => item.name,
          detail: (item) => item.address ?? '地点结果',
          onTap: onSearchResult,
        ),
      );
    }
    return places.when(
      loading: () => const V2LoadingObject(label: '正在整理附近线索'),
      error: (_, _) => Center(
        child: V2Pressable(
          onTap: onSearchMapArea,
          color: V2Palette.mossSoft,
          compact: true,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text('搜索当前地图区域'),
          ),
        ),
      ),
      data: (items) => _V2ResultList<NearbyPlace>(
        items: items,
        title: (item) => item.name,
        detail: _placeDetail,
        onTap: onPlace,
      ),
    );
  }

  static String _placeDetail(NearbyPlace place) => [
    _distance(place.distanceMeters),
    if (place.address?.isNotEmpty == true) place.address!,
    if (place.isOfflineCache) '离线缓存',
  ].join(' · ');

  static String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';
}

class _V2ResultList<T> extends StatelessWidget {
  const _V2ResultList({
    required this.items,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final List<T> items;
  final String Function(T) title;
  final String Function(T) detail;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('这个范围暂无线索'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () => onTap(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.location_solid,
                  color: V2Palette.moss,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(item),
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _V2SelectedPlace extends StatelessWidget {
  const _V2SelectedPlace({
    required this.name,
    required this.detail,
    required this.onRoute,
    this.saved = false,
    this.onSave,
  });
  final String name;
  final String detail;
  final bool saved;
  final VoidCallback? onSave;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        const Icon(CupertinoIcons.scope, color: V2Palette.moss, size: 38),
        const SizedBox(height: 18),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 9),
        Text(detail, style: const TextStyle(color: V2Palette.mutedInk)),
        const Spacer(),
        Row(
          children: [
            if (onSave != null) ...[
              V2RoundAction(
                icon: saved
                    ? CupertinoIcons.bookmark_fill
                    : CupertinoIcons.bookmark,
                label: saved ? '取消收藏' : '收藏',
                onTap: onSave!,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: V2Pressable(
                onTap: onRoute,
                color: V2Palette.moss,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '规划路线',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
