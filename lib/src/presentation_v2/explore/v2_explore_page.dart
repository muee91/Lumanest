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
import 'package:luma_nest/src/features/explore/presentation/amap_marker_icon_factory.dart';
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
  GeoPoint? _latestMapLocation;
  AsyncValue<List<LocationSearchResult>>? _searchResults;
  NearbyPlace? _selectedPlace;
  LocationSearchResult? _selectedSearchResult;
  AmapExploreMarkerIcons? _markerIcons;
  int _searchGeneration = 0;
  double _panelFraction = .12;
  bool _initialized = false;
  bool _intentPickerOpen = false;
  bool _ignoreNextCameraMoveEnd = false;

  @override
  void initState() {
    super.initState();
    if (widget.focus == ExploreFocus.sunrise ||
        widget.focus == ExploreFocus.nightSky) {
      _panelFraction = .5;
    }
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadMarkerIcons());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(exploreIntentProvider.notifier).activate(widget.focus);
      if (widget.focus == ExploreFocus.sunrise ||
          widget.focus == ExploreFocus.nightSky) {
        ref.read(nearbySearchAreaProvider.notifier).useDrivingCandidateRadius();
      } else {
        ref.read(nearbySearchAreaProvider.notifier).resetRadius();
      }
    });
  }

  Future<void> _loadMarkerIcons() async {
    final icons = await AmapMarkerIconFactory.build();
    if (!mounted) return;
    setState(() => _markerIcons = icons);
  }

  @override
  void didUpdateWidget(covariant _V2ExploreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus == widget.focus) return;
    if (widget.focus == ExploreFocus.sunrise ||
        widget.focus == ExploreFocus.nightSky) {
      _panelFraction = .5;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(exploreIntentProvider.notifier).activate(widget.focus);
      if (widget.focus == ExploreFocus.sunrise ||
          widget.focus == ExploreFocus.nightSky) {
        ref.read(nearbySearchAreaProvider.notifier).useDrivingCandidateRadius();
      } else {
        ref.read(nearbySearchAreaProvider.notifier).resetRadius();
      }
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
    final generation = ++_searchGeneration;
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
        if (mounted && generation == _searchGeneration) {
          setState(() => _searchResults = AsyncData(result));
        }
      } on Object catch (error, stack) {
        if (mounted && generation == _searchGeneration) {
          setState(() => _searchResults = AsyncError(error, stack));
        }
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
    final searchArea = ref.watch(nearbySearchAreaProvider);
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
              onLocationChanged: (location) {
                _latestMapLocation = GeoPoint(
                  latitude: location.latLng.latitude,
                  longitude: location.latLng.longitude,
                  coordinateSystem: CoordinateSystem.gcj02,
                );
              },
              compassEnabled: false,
              scaleEnabled: false,
              markers: markers,
              onTap: (_) {
                if (_intentPickerOpen) {
                  setState(() => _intentPickerOpen = false);
                }
              },
              onCameraMoveEnd: (position) {
                if (_ignoreNextCameraMoveEnd) {
                  _ignoreNextCameraMoveEnd = false;
                  return;
                }
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
                expanded: _intentPickerOpen,
                onOpen: () =>
                    setState(() => _intentPickerOpen = !_intentPickerOpen),
              ),
            ),
            Positioned(
              right: 18,
              top: MediaQuery.paddingOf(context).top + 82,
              child: _V2MapControlButton(
                icon: CupertinoIcons.location_fill,
                label: '回到当前位置',
                onTap: () => _returnToCurrentLocation(origin),
              ),
            ),
            if (searchArea.hasPendingMapArea && !_intentPickerOpen)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.paddingOf(context).top + 142,
                child: Center(
                  child: _V2SearchMapAreaObject(onTap: _searchCurrentMapArea),
                ),
              ),
            if (_intentPickerOpen)
              Positioned(
                left: 18,
                right: 18,
                top: MediaQuery.paddingOf(context).top + 142,
                child: _V2IntentPickerObject(
                  selectedCategory: intent.category,
                  onSelect: _selectExploreIntent,
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
                focus: intent.activeFocus,
                category: intent.category,
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
                onClearSelection: _clearSelection,
                onRoute: _openRoute,
                onSave: _toggleSave,
                onSearchMapArea: _searchCurrentMapArea,
                onMediaResolved: _resolveSelectedMediaLayout,
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectExploreIntent(ExploreCreativeIntent intent) {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    ref.read(exploreIntentProvider.notifier).chooseCreativeIntent(intent);
    ref.read(nearbySearchAreaProvider.notifier).resetRadius();
    setState(() {
      _intentPickerOpen = false;
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .5;
    });
  }

  void _searchCurrentMapArea() {
    ref.read(nearbySearchAreaProvider.notifier).searchPendingArea();
    setState(() {
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .5;
    });
  }

  void _returnToCurrentLocation(GeoPoint origin) {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    final point =
        _latestMapLocation ?? ChinaCoordinateConverter.wgs84ToGcj02(origin);
    final queryCenter = point.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(point)
        : point;
    ref.read(nearbySearchAreaProvider.notifier).returnToLocation(queryCenter);
    final controller = _mapController;
    if (controller != null) {
      _ignoreNextCameraMoveEnd = true;
      unawaited(
        controller.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(point.latitude, point.longitude),
              zoom: 13,
            ),
          ),
          duration: 520,
        ),
      );
    }
    setState(() {
      _intentPickerOpen = false;
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .12;
    });
  }

  Set<Marker> _markers(AsyncValue<List<NearbyPlace>> places) {
    final icons = _markerIcons;
    if (icons == null) return const <Marker>{};
    final result = <Marker>{};
    for (final place in places.asData?.value ?? const <NearbyPlace>[]) {
      final point = ChinaCoordinateConverter.wgs84ToGcj02(place.point);
      final selected = _selectedPlace?.id == place.id;
      result.add(
        Marker(
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(title: place.name),
          icon: selected
              ? icons.selected[place.category]!
              : icons.regular[place.category]!,
          anchor: const Offset(.5, .92),
          onTap: (_) => _selectPlace(place),
          zIndex: selected ? 2 : 1,
        ),
      );
    }
    for (final item
        in _searchResults?.asData?.value ?? const <LocationSearchResult>[]) {
      final point = ChinaCoordinateConverter.wgs84ToGcj02(item.point);
      final selected = _selectedSearchResult?.id == item.id;
      result.add(
        Marker(
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(title: item.name),
          icon: selected ? icons.selectedSearch : icons.search,
          anchor: const Offset(.5, .92),
          onTap: (_) => _selectSearchResult(item),
          zIndex: selected ? 3 : 1,
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
      _panelFraction = .68;
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

  void _resolveSelectedMediaLayout(bool hasMedia) {
    if (!mounted || _selectedPlace == null) return;
    final next = hasMedia ? .68 : .5;
    if (_panelFraction == next) return;
    setState(() => _panelFraction = next);
  }

  void _clearSelection() {
    setState(() {
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .68;
    });
  }

  void _focusPoint(GeoPoint point) {
    final gcj = ChinaCoordinateConverter.wgs84ToGcj02(point);
    _ignoreNextCameraMoveEnd = true;
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
    required this.expanded,
    required this.onOpen,
  });
  final ExploreCreativeIntent? intent;
  final NearbyPlaceCategory category;
  final bool expanded;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onOpen,
    compact: true,
    color: V2Palette.night,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_intentIcon(category), color: Colors.white, size: 18),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                intent?.label ?? _categoryTitle(category),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                category == NearbyPlaceCategory.waterfront
                    ? '地点筛选 · 未判断倒影'
                    : '选择探索主题',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 9),
          Icon(
            expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
            color: Colors.white70,
            size: 13,
          ),
        ],
      ),
    ),
  );
}

class _V2IntentPickerObject extends StatelessWidget {
  const _V2IntentPickerObject({
    required this.selectedCategory,
    required this.onSelect,
  });

  final NearbyPlaceCategory selectedCategory;
  final ValueChanged<ExploreCreativeIntent> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: V2Palette.paper,
    elevation: 20,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择探索主题',
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            '这是地点筛选，不代表拍摄条件已经成立。',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in ExploreCreativeIntent.values)
                    SizedBox(
                      width: width,
                      child: _V2IntentChoice(
                        intent: item,
                        selected: selectedCategory == item.category,
                        onTap: () => onSelect(item),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _V2IntentChoice extends StatelessWidget {
  const _V2IntentChoice({
    required this.intent,
    required this.selected,
    required this.onTap,
  });

  final ExploreCreativeIntent intent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    compact: true,
    color: selected ? V2Palette.mossSoft : V2Palette.canvas,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      child: Row(
        children: [
          Icon(
            _intentIcon(intent.category),
            color: selected ? V2Palette.moss : V2Palette.ink,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              intent.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _V2MapControlButton extends StatelessWidget {
  const _V2MapControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: Material(
        color: V2Palette.paper,
        elevation: 11,
        shadowColor: Colors.black26,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: V2Palette.ink, size: 21),
          ),
        ),
      ),
    ),
  );
}

class _V2SearchMapAreaObject extends StatelessWidget {
  const _V2SearchMapAreaObject({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    compact: true,
    color: V2Palette.paper,
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.search, color: V2Palette.ink, size: 15),
          SizedBox(width: 7),
          Text(
            '搜索此区域',
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

IconData _intentIcon(NearbyPlaceCategory category) => switch (category) {
  NearbyPlaceCategory.viewpoint => Icons.photo_camera_outlined,
  NearbyPlaceCategory.sunriseCandidate => Icons.wb_sunny_rounded,
  NearbyPlaceCategory.nightSkyCandidate => Icons.nightlight_round,
  NearbyPlaceCategory.waterfront => Icons.water_rounded,
  NearbyPlaceCategory.humanity => Icons.account_balance_outlined,
  NearbyPlaceCategory.fuel => Icons.local_gas_station_outlined,
  NearbyPlaceCategory.food => Icons.restaurant_rounded,
  NearbyPlaceCategory.supply => Icons.shopping_bag_outlined,
  NearbyPlaceCategory.parking => Icons.local_parking_rounded,
  NearbyPlaceCategory.medical => Icons.local_hospital_outlined,
};

String _categoryTitle(NearbyPlaceCategory category) => switch (category) {
  NearbyPlaceCategory.viewpoint => '观景线索',
  NearbyPlaceCategory.sunriseCandidate => '日出候选',
  NearbyPlaceCategory.nightSkyCandidate => '夜空候选',
  NearbyPlaceCategory.waterfront => '水岸线索',
  NearbyPlaceCategory.humanity => '人文街巷',
  NearbyPlaceCategory.fuel => '加油地点',
  NearbyPlaceCategory.food => '餐饮地点',
  NearbyPlaceCategory.supply => '拍摄补给',
  NearbyPlaceCategory.parking => '停车地点',
  NearbyPlaceCategory.medical => '医疗地点',
};

class _V2ExploreResultObject extends ConsumerWidget {
  const _V2ExploreResultObject({
    required this.focus,
    required this.category,
    required this.places,
    required this.searchResults,
    required this.selectedPlace,
    required this.selectedSearchResult,
    required this.expanded,
    required this.onDrag,
    required this.onSnap,
    required this.onPlace,
    required this.onSearchResult,
    required this.onClearSelection,
    required this.onRoute,
    required this.onSave,
    required this.onSearchMapArea,
    required this.onMediaResolved,
  });
  final ExploreFocus? focus;
  final NearbyPlaceCategory category;
  final AsyncValue<List<NearbyPlace>> places;
  final AsyncValue<List<LocationSearchResult>>? searchResults;
  final NearbyPlace? selectedPlace;
  final LocationSearchResult? selectedSearchResult;
  final bool expanded;
  final ValueChanged<double> onDrag;
  final VoidCallback onSnap;
  final ValueChanged<NearbyPlace> onPlace;
  final ValueChanged<LocationSearchResult> onSearchResult;
  final VoidCallback onClearSelection;
  final void Function(String, GeoPoint) onRoute;
  final ValueChanged<NearbyPlace> onSave;
  final VoidCallback onSearchMapArea;
  final ValueChanged<bool> onMediaResolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    final serviceToken = ref
        .watch(environmentConfigProvider)
        .lumaNestServiceToken;
    final mediaHeaders = serviceToken.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $serviceToken'};
    final selectedMedia = selectedPlace == null
        ? null
        : ref.watch(verifiedPlaceMediaProvider(selectedPlace!));
    if (selectedMedia != null && !selectedMedia.isLoading) {
      final media = selectedMedia.asData?.value ?? selectedPlace?.coverMedia;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onMediaResolved(media != null);
      });
    }
    final candidateCount = places.asData?.value.length;
    final candidateMode =
        focus == ExploreFocus.sunrise || focus == ExploreFocus.nightSky;
    final defaultTitle = switch (focus) {
      ExploreFocus.sunrise =>
        candidateCount == null ? '正在整理日出候选' : '明日日出 · $candidateCount处候选',
      ExploreFocus.nightSky =>
        candidateCount == null ? '正在整理夜空候选' : '夜空拍摄 · $candidateCount处候选',
      _ => searchResults == null ? '附近${_categoryTitle(category)}' : '搜索结果',
    };
    final headerTitle = selectedPlace != null
        ? candidateMode
              ? '候选详情'
              : '地点详情'
        : selectedSearchResult != null
        ? '地点详情'
        : defaultTitle;
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
                          headerTitle,
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
                        expanded
                            ? '收起'
                            : candidateMode
                            ? '上拉看候选'
                            : '向上探索',
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
          if (expanded)
            Expanded(
              child: _body(
                context,
                library,
                candidateMode: candidateMode,
                candidateCount: candidateCount ?? 0,
                mediaHeaders: mediaHeaders,
                selectedMedia: selectedMedia,
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    UserLibraryState? library, {
    required bool candidateMode,
    required int candidateCount,
    required Map<String, String>? mediaHeaders,
    required AsyncValue<NearbyPlaceMedia?>? selectedMedia,
  }) {
    final selected = selectedPlace;
    if (selected != null) {
      final verifiedMedia = selectedMedia?.asData?.value;
      final amapFallbackMedia = selected.coverMedia;
      final resolvedMedia = selectedMedia == null || selectedMedia.isLoading
          ? null
          : verifiedMedia ?? amapFallbackMedia;
      return _V2SelectedPlace(
        name: selected.name,
        eyebrow: candidateMode
            ? selected.category.label
            : _categoryTitle(selected.category),
        detail: candidateMode
            ? _candidateDetail(selected)
            : _placeDetail(selected),
        saved: library?.containsPlace(selected.id) == true,
        onBack: candidateMode ? onClearSelection : null,
        backLabel: '返回$candidateCount处候选',
        onSave: () => onSave(selected),
        onRoute: () => onRoute(selected.name, selected.point),
        routeLabel: candidateMode ? '查看驾车路线' : '规划路线',
        media: resolvedMedia,
        fallbackMedia: verifiedMedia == null ? null : amapFallbackMedia,
        mediaLoading: selectedMedia?.isLoading == true,
        mediaHeaders: mediaHeaders,
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
      data: (items) {
        if (items.isEmpty) {
          return _V2NoNearbyResults(category: category);
        }
        return Column(
          children: [
            if (candidateMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(18, 4, 18, 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: V2Palette.mossSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '行政区＋50公里＋驾车时间综合排序 · 有来源的AI资料仅加权',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (!candidateMode && category == NearbyPlaceCategory.waterfront)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(18, 4, 18, 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.water_rounded,
                      color: Color(0xFF4F9297),
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '这里只表示附近有水岸地点；是否适合倒影，还需结合风、光线和明确主体。',
                        style: TextStyle(
                          color: V2Palette.ink,
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _V2ResultList<NearbyPlace>(
                items: items,
                title: (item) => item.name,
                detail: (item) => candidateMode
                    ? '候选 · ${_candidateDetail(item)}'
                    : _placeDetail(item),
                onTap: onPlace,
                rankedCandidates: candidateMode,
              ),
            ),
          ],
        );
      },
    );
  }

  static String _placeDetail(NearbyPlace place) => [
    _distance(place.distanceMeters),
    if (place.address?.isNotEmpty == true) place.address!,
    if (place.isOfflineCache) '离线缓存',
  ].join(' · ');

  static String _candidateDetail(NearbyPlace place) {
    final parts = <String>[];
    if (place.administrativeLabel case final label?) parts.add(label);
    if (place.drivingDurationSeconds case final seconds?) {
      parts.add('驾车${_duration(seconds)}');
    }
    parts.add(_distance(place.drivingDistanceMeters ?? place.distanceMeters));
    if (place.sourceEvidenceCount > 0) {
      parts.add('${place.sourceEvidenceCount}条来源佐证');
    }
    if (place.isOfflineCache) parts.add('离线缓存');
    return parts.join(' · ');
  }

  static String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  static String _duration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes分钟';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '$hours小时' : '$hours小时$remaining分钟';
  }
}

class _V2NoNearbyResults extends StatelessWidget {
  const _V2NoNearbyResults({required this.category});

  final NearbyPlaceCategory category;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_intentIcon(category), color: V2Palette.moss, size: 31),
          const SizedBox(height: 12),
          Text(
            '附近暂未找到${_categoryTitle(category)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '移动地图后选择“搜索此区域”，或换一个探索主题。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _V2ResultList<T> extends StatelessWidget {
  const _V2ResultList({
    required this.items,
    required this.title,
    required this.detail,
    required this.onTap,
    this.rankedCandidates = false,
  });
  final List<T> items;
  final String Function(T) title;
  final String Function(T) detail;
  final ValueChanged<T> onTap;
  final bool rankedCandidates;

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
                if (rankedCandidates)
                  _V2CandidateRankBadge(rank: index + 1)
                else
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

class _V2CandidateRankBadge extends StatelessWidget {
  const _V2CandidateRankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: V2Palette.mossSoft,
      shape: BoxShape.circle,
    ),
    child: Text(
      '$rank',
      style: const TextStyle(
        color: V2Palette.moss,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _V2SelectedPlace extends StatelessWidget {
  const _V2SelectedPlace({
    required this.name,
    required this.detail,
    required this.onRoute,
    this.eyebrow,
    this.saved = false,
    this.onSave,
    this.onBack,
    this.backLabel = '返回候选',
    this.routeLabel = '规划路线',
    this.media,
    this.fallbackMedia,
    this.mediaLoading = false,
    this.mediaHeaders,
  });
  final String name;
  final String detail;
  final String? eyebrow;
  final bool saved;
  final VoidCallback? onSave;
  final VoidCallback? onBack;
  final String backLabel;
  final String routeLabel;
  final VoidCallback onRoute;
  final NearbyPlaceMedia? media;
  final NearbyPlaceMedia? fallbackMedia;
  final bool mediaLoading;
  final Map<String, String>? mediaHeaders;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null)
          TextButton.icon(
            onPressed: onBack,
            style: TextButton.styleFrom(foregroundColor: V2Palette.moss),
            icon: const Icon(CupertinoIcons.chevron_left, size: 16),
            label: Text(backLabel),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: switch ((mediaLoading, media)) {
            (_, final item?) => _V2PlaceDetailPhoto(
              key: ValueKey(item.id),
              media: item,
              fallbackMedia: fallbackMedia,
              headers: mediaHeaders,
            ),
            (true, _) => const _V2PlacePhotoLoading(),
            _ => const SizedBox.shrink(),
          },
        ),
        SizedBox(height: media != null || mediaLoading ? 16 : 8),
        if (eyebrow case final label?) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: V2Palette.mossSoft,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                label,
                style: const TextStyle(
                  color: V2Palette.moss,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 26,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 13,
            height: 1.45,
          ),
        ),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    routeLabel,
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

class _V2PlacePhotoLoading extends StatelessWidget {
  const _V2PlacePhotoLoading();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('place-photo-loading'),
    height: 112,
    decoration: BoxDecoration(
      color: V2Palette.canvas,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: V2Palette.line),
    ),
    child: const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.photo, color: V2Palette.mutedInk, size: 19),
          SizedBox(width: 9),
          Text(
            '正在核对地点图片',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _V2PlaceDetailPhoto extends StatefulWidget {
  const _V2PlaceDetailPhoto({
    required this.media,
    required this.fallbackMedia,
    required this.headers,
    super.key,
  });

  final NearbyPlaceMedia media;
  final NearbyPlaceMedia? fallbackMedia;
  final Map<String, String>? headers;

  @override
  State<_V2PlaceDetailPhoto> createState() => _V2PlaceDetailPhotoState();
}

class _V2PlaceDetailPhotoState extends State<_V2PlaceDetailPhoto> {
  bool _failed = false;
  late NearbyPlaceMedia _activeMedia = widget.media;

  @override
  void didUpdateWidget(covariant _V2PlaceDetailPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.url != widget.media.url) {
      _activeMedia = widget.media;
      _failed = false;
    }
  }

  void _hideFailedImage() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fallback = widget.fallbackMedia;
      if (fallback != null && fallback.url != _activeMedia.url) {
        setState(() => _activeMedia = fallback);
      } else {
        setState(() => _failed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: double.infinity,
        height: 156,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _activeMedia.url,
              headers: widget.headers,
              fit: BoxFit.cover,
              cacheWidth: 900,
              gaplessPlayback: true,
              semanticLabel:
                  '${_activeMedia.title ?? '候选地点'}地点资料照片，来源${_activeMedia.attribution}',
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const ColoredBox(
                      color: V2Palette.canvas,
                      child: Center(
                        child: Icon(
                          CupertinoIcons.photo,
                          color: V2Palette.line,
                          size: 24,
                        ),
                      ),
                    ),
              errorBuilder: (_, _, _) {
                _hideFailedImage();
                return const SizedBox.shrink();
              },
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x66000000)],
                    stops: [.55, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 9,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  child: Text(
                    switch (_activeMedia.matchBasis) {
                      'coordinate' => '已按地点坐标核对',
                      'name' => '已按地点名称核对',
                      _ => '平台资料图 · 仅供辨认',
                    },
                    style: const TextStyle(
                      color: V2Palette.ink,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 9,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  child: Text(
                    _activeMedia.attribution == '高德地图'
                        ? '地点资料图 · 高德参考'
                        : '地点资料图 · ${_activeMedia.attribution}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
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
