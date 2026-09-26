import 'dart:async';
import 'dart:ui';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/core/environment/provider_facts_providers.dart';
import 'package:luma_nest/src/core/environment/provider_signal_relevance.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_catalog.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/explore_composition_engine.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_photo_theme_focus.dart';
import 'package:luma_nest/src/features/explore/presentation/amap_marker_icon_factory.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/presentation_v2/explore/v2_provider_facts_sheet.dart';
import 'package:luma_nest/src/presentation_v2/explore/v2_region_brief_expansion.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:x_amap_base/x_amap_base.dart';

class V2ExplorePage extends ConsumerWidget {
  const V2ExplorePage({
    super.key,
    this.focus = ExploreFocus.photography,
    this.placeId,
  });

  final ExploreFocus focus;
  final String? placeId;

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
    final snapshot = ref.watch(environmentSnapshotProvider).asData?.value;
    final briefState = ref.watch(regionBriefControllerProvider);
    final providerFacts = ref.watch(providerFactsProvider).asData?.value;
    final composition = const ExploreCompositionEngine().compose(
      snapshot: snapshot,
      brief: briefState.brief,
    );
    final providerSignals = switch ((providerFacts, snapshot)) {
      (final facts?, final currentSnapshot?) => selectProviderSignalsForContext(
        facts,
        currentSnapshot,
      ),
      _ => const <ProviderSignal>[],
    };
    void openMapFor(ExploreFocus selectedFocus) {
      switch (ref.read(mapConsentControllerProvider)) {
        case MapConsentReady():
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  _V2ExploreMap(focus: selectedFocus, placeId: placeId),
            ),
          );
        case MapConsentAwaiting():
          ref.read(mapConsentControllerProvider.notifier).grantConsent();
        case MapConsentConfigurationMissing():
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('地图尚未配置，区域简报仍可使用。')));
      }
    }

    if (composition.showsBriefFirst && briefState.brief != null) {
      return _V2ExploreBrief(
        brief: briefState.brief!,
        state: briefState,
        providerFacts: providerFacts,
        providerSignals: providerSignals,
        refreshing: briefState.status == RegionBriefLoadStatus.refreshing,
        onRefresh: () =>
            ref.read(regionBriefControllerProvider.notifier).load(manual: true),
        onVerify: () => ref
            .read(regionBriefControllerProvider.notifier)
            .load(verification: true),
        onOpenMap: () => openMapFor(focus),
        onOpenTheme: (theme) => openMapFor(focusForRegionPhotoTheme(theme)),
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
      MapConsentReady() => _V2ExploreMap(focus: focus, placeId: placeId),
    };
  }
}

class _V2ExploreBrief extends StatelessWidget {
  const _V2ExploreBrief({
    required this.brief,
    required this.state,
    required this.providerFacts,
    required this.providerSignals,
    required this.refreshing,
    required this.onRefresh,
    required this.onVerify,
    required this.onOpenMap,
    required this.onOpenTheme,
  });

  final RegionBrief brief;
  final RegionBriefState state;
  final ProviderFactsBundle? providerFacts;
  final List<ProviderSignal> providerSignals;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onVerify;
  final VoidCallback onOpenMap;
  final ValueChanged<RegionPhotoTheme> onOpenTheme;

  @override
  Widget build(BuildContext context) {
    final sections = brief.insights
        .where(
          (item) =>
              item.type != RegionInsightType.areaIdentity &&
              item.type != RegionInsightType.orientation,
        )
        .toList(growable: false);
    return Scaffold(
      backgroundColor: V2Palette.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      brief.regionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '打开地图',
                    onPressed: onOpenMap,
                    icon: const Icon(CupertinoIcons.map),
                  ),
                ],
              ),
              if (refreshing) ...[
                const SizedBox(height: 4),
                Text(
                  state.isVerifying
                      ? '正在核验候选与冲突信息'
                      : state.isExpanding
                      ? '正在扩展区域资料'
                      : '正在更新区域资料',
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _V2BriefCard(
                eyebrow: '这里是什么',
                title: brief.identity!.summary,
                detail: brief.orientation!.summary,
              ),
              if (brief.photoThemes.isNotEmpty) ...[
                const SizedBox(height: 14),
                _V2BriefThemeCard(
                  themes: brief.photoThemes,
                  onOpenTheme: onOpenTheme,
                ),
              ],
              const SizedBox(height: 14),
              V2RegionBriefExpansionCard(
                brief: brief,
                state: state,
                onExpand: onRefresh,
                onVerify: onVerify,
              ),
              if (providerSignals.isNotEmpty) ...[
                const SizedBox(height: 14),
                V2ProviderFactsSummaryCard(
                  bundle: providerFacts!,
                  signals: providerSignals,
                  onTap: () => showV2ProviderFactsSheet(
                    context,
                    providerFacts!,
                    prioritizedSignals: providerSignals,
                  ),
                ),
              ],
              if (sections.isNotEmpty) ...[
                const SizedBox(height: 22),
                V2RegionBriefInsightSections(insights: sections),
              ],
              const SizedBox(height: 18),
              V2Pressable(
                onTap: onOpenMap,
                color: V2Palette.mossSoft,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.map, color: V2Palette.moss, size: 18),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '打开地图与附近地点',
                          style: TextStyle(
                            color: V2Palette.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: V2Palette.moss,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _V2BriefCard extends StatelessWidget {
  const _V2BriefCard({
    required this.eyebrow,
    required this.title,
    required this.detail,
  });

  final String eyebrow;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: V2Palette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: V2Palette.moss,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ],
    ),
  );
}

class _V2BriefThemeCard extends StatelessWidget {
  const _V2BriefThemeCard({required this.themes, required this.onOpenTheme});

  final List<RegionPhotoTheme> themes;
  final ValueChanged<RegionPhotoTheme> onOpenTheme;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: V2Palette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '区域题材',
          style: TextStyle(
            color: V2Palette.moss,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '点击题材查看附近线索',
          style: TextStyle(
            color: V2Palette.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '题材来自场景和已验证区域资料，不替代具体机位。',
          style: TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final theme in themes)
              _V2BriefThemeAction(
                key: Key('v2-explore-brief-theme-${theme.id}'),
                theme: theme,
                onTap: () => onOpenTheme(theme),
              ),
          ],
        ),
      ],
    ),
  );
}

class _V2BriefThemeAction extends StatelessWidget {
  const _V2BriefThemeAction({
    super.key,
    required this.theme,
    required this.onTap,
  });

  final RegionPhotoTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '查看${theme.label}附近线索',
    child: Material(
      color: V2Palette.mossSoft,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                theme.label,
                style: const TextStyle(
                  color: V2Palette.moss,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                CupertinoIcons.arrow_up_right,
                color: V2Palette.moss,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _V2ExploreMap extends ConsumerStatefulWidget {
  const _V2ExploreMap({required this.focus, this.placeId});
  final ExploreFocus focus;
  final String? placeId;

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
  double _panelFraction = 0;
  bool _panelDragging = false;
  bool _initialized = false;
  bool _searchOpen = false;
  bool _ignoreNextCameraMoveEnd = false;
  Timer? _ignoreCameraResetTimer;
  bool? _lastMediaResolved;

  @override
  void initState() {
    super.initState();
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
    _panelFraction = 0;
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
    _ignoreCameraResetTimer?.cancel();
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

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _panelFraction = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchOpen = false;
      _searchResults = null;
      _panelFraction = 0;
    });
  }

  void _selectSearchShortcut(ExploreCreativeIntent intent) {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    ref.read(exploreIntentProvider.notifier).chooseCreativeIntent(intent);
    ref.read(nearbySearchAreaProvider.notifier).resetRadius();
    setState(() {
      _searchOpen = false;
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .68;
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
    _selectInitialPlace(places);
    final intent = ref.watch(exploreIntentProvider);
    final regionThemes = selectExploreRegionThemes(
      ref.watch(regionBriefControllerProvider).brief?.photoThemes ??
          const <RegionPhotoTheme>[],
    );
    final searchArea = ref.watch(nearbySearchAreaProvider);
    final providerFacts = ref.watch(providerFactsProvider).asData?.value;
    final providerSignals = providerFacts == null
        ? const <ProviderSignal>[]
        : selectProviderSignalsForContext(providerFacts, snapshot);
    final mapCenter = ChinaCoordinateConverter.wgs84ToGcj02(origin);
    final markers = _markers(places);

    return LayoutBuilder(
      builder: (context, constraints) {
        // `padding.bottom` inside an extended Scaffold already includes the
        // navigation bar; use the physical safe inset to avoid counting the
        // dock twice and leaving a gap below the handle.
        final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
        final bottomInset = _searchOpen
            ? MediaQuery.viewInsetsOf(context).bottom
            : 0.0;
        // Keep the sheet attached to the physical bottom like the reference.
        // Its collapsed body sits behind navigation and only the top handle
        // remains visible above the dock.
        final navigationClearance = 64 + 12 + bottomSafeArea;
        final availablePanelHeight = constraints.maxHeight - bottomInset;
        final collapsedPanelHeight = navigationClearance + 72;
        final collapsedPanelFraction =
            collapsedPanelHeight / availablePanelHeight;
        final effectivePanelFraction = _panelFraction.clamp(
          collapsedPanelFraction,
          .82,
        );
        final panelExpanded =
            effectivePanelFraction > collapsedPanelFraction + .04;
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
            if (_searchOpen)
              Positioned(
                left: 18,
                right: 18,
                top: MediaQuery.paddingOf(context).top + 12,
                child: _V2SearchObject(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onClose: _closeSearch,
                  onClear: () => _searchController.clear(),
                ),
              )
            else
              Positioned(
                right: 18,
                top: MediaQuery.paddingOf(context).top + 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (providerSignals.isNotEmpty) ...[
                      _V2MapControlButton(
                        key: const Key('v2-explore-provider-facts-button'),
                        icon: CupertinoIcons.layers,
                        label: '查看环境与地区数据',
                        onTap: () => showV2ProviderFactsSheet(
                          context,
                          providerFacts!,
                          prioritizedSignals: providerSignals,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _V2MapControlButton(
                      key: const Key('v2-explore-search-button'),
                      icon: CupertinoIcons.search,
                      label: '选择地点或搜索',
                      onTap: _openSearch,
                    ),
                  ],
                ),
              ),
            if (!_searchOpen)
              Positioned(
                left: 18,
                top: MediaQuery.paddingOf(context).top + 12,
                child: _V2MapControlButton(
                  icon: CupertinoIcons.location_fill,
                  label: '回到当前位置',
                  onTap: () => _returnToCurrentLocation(origin),
                ),
              ),
            if (_searchOpen && _searchController.text.trim().isEmpty)
              Positioned(
                left: 18,
                right: 18,
                top: MediaQuery.paddingOf(context).top + 82,
                child: _V2SearchShortcutObject(onSelect: _selectSearchShortcut),
              ),
            if (!_searchOpen)
              Positioned(
                left: 18,
                right: 18,
                top: MediaQuery.paddingOf(context).top + 68,
                child: _V2IntentStrip(
                  intent: intent,
                  regionThemes: regionThemes,
                  onSelect: _selectExploreIntent,
                  onSelectRegionTheme: _selectRegionTheme,
                ),
              ),
            if (searchArea.hasPendingMapArea && !_searchOpen)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.paddingOf(context).top + 116,
                child: Center(
                  child: _V2SearchMapAreaObject(onTap: _searchCurrentMapArea),
                ),
              ),
            AnimatedPositioned(
              key: const Key('v2-explore-results-panel'),
              duration: _panelDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: bottomInset,
              height: availablePanelHeight * effectivePanelFraction,
              child: _V2ExploreResultObject(
                focus: intent.activeFocus,
                category: intent.category,
                places: places,
                searchResults: _searchResults,
                selectedPlace: _selectedPlace,
                selectedSearchResult: _selectedSearchResult,
                expanded: panelExpanded,
                bottomContentInset: navigationClearance,
                regionLabel: _regionLabel(snapshot),
                onDragStart: () => setState(() {
                  _panelDragging = true;
                  _panelFraction = effectivePanelFraction;
                }),
                onDragUpdate: (delta) => setState(() {
                  _panelFraction =
                      (_panelFraction - delta / availablePanelHeight).clamp(
                        collapsedPanelFraction,
                        .82,
                      );
                }),
                onDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  final target = velocity <= -550
                      ? .82
                      : velocity >= 550
                      ? collapsedPanelFraction
                      : _panelFraction >= .38
                      ? .82
                      : collapsedPanelFraction;
                  unawaited(HapticFeedback.lightImpact());
                  setState(() {
                    _panelDragging = false;
                    _panelFraction = target;
                  });
                },
                onToggle: () {
                  unawaited(HapticFeedback.lightImpact());
                  setState(() {
                    _panelDragging = false;
                    _panelFraction = panelExpanded
                        ? collapsedPanelFraction
                        : .82;
                  });
                },
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

  String _regionLabel(ContextSnapshot snapshot) {
    return switch (snapshot.primaryScene) {
      SceneType.city => '城市附近',
      SceneType.lake => '水岸附近',
      SceneType.mountain => '山地附近',
      SceneType.desert => '荒野附近',
      SceneType.village => '村落附近',
      SceneType.unknown => '当前区域',
    };
  }

  void _selectInitialPlace(AsyncValue<List<NearbyPlace>> places) {
    final id = widget.placeId;
    if (id == null || _selectedPlace != null) return;
    final match = places.asData?.value
        .where((place) => place.id == id)
        .firstOrNull;
    if (match == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedPlace != null) return;
      setState(() {
        _selectedPlace = match;
        _selectedSearchResult = null;
        _panelFraction = .5;
      });
      _focusPoint(match.point);
    });
  }

  void _selectExploreIntent(ExploreCreativeIntent intent) {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    ref.read(exploreIntentProvider.notifier).chooseCreativeIntent(intent);
    ref.read(nearbySearchAreaProvider.notifier).resetRadius();
    setState(() {
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .5;
    });
  }

  void _selectRegionTheme(RegionPhotoTheme theme) {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    ref.read(exploreIntentProvider.notifier).chooseRegionTheme(theme);
    ref.read(nearbySearchAreaProvider.notifier).resetRadius();
    setState(() {
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .5;
    });
  }

  void _searchCurrentMapArea() {
    final hasPendingArea = ref.read(nearbySearchAreaProvider).hasPendingMapArea;
    ref.read(nearbySearchAreaProvider.notifier).searchPendingArea();
    // In the empty state the map may not have moved yet.  Keep this action
    // meaningful by refreshing the current area instead of presenting a dead
    // control.
    if (!hasPendingArea) ref.invalidate(nearbyPlacesProvider);
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
      _setIgnoreNextCameraMoveEnd();
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
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .68;
    });
  }

  Set<Marker> _markers(AsyncValue<List<NearbyPlace>> places) {
    final icons = _markerIcons;
    if (icons == null) return const <Marker>{};
    final result = <Marker>{};
    final nearbyPoints = <GeoPoint>[];
    for (final place in places.asData?.value ?? const <NearbyPlace>[]) {
      final point = ChinaCoordinateConverter.wgs84ToGcj02(place.point);
      nearbyPoints.add(place.point);
      final selected = _selectedPlace?.id == place.id;
      final marker = Marker(
        position: LatLng(point.latitude, point.longitude),
        infoWindow: InfoWindow(title: place.name),
        icon: selected
            ? icons.selected[place.category]!
            : icons.regular[place.category]!,
        anchor: const Offset(.5, .92),
        onTap: (_) => _selectPlace(place),
        zIndex: selected ? 2 : 1,
      )..setIdForCopy('nearby:${place.id}');
      result.add(marker);
    }
    for (final item
        in _searchResults?.asData?.value ?? const <LocationSearchResult>[]) {
      // Skip search results that overlap with an existing nearby place marker
      // (within ~50m, approx 0.00045° lat) to avoid ambiguous tap targets.
      final tooClose = nearbyPoints.any(
        (p) =>
            (p.latitude - item.point.latitude).abs() < 0.00045 &&
            (p.longitude - item.point.longitude).abs() < 0.00045,
      );
      if (tooClose) continue;
      final point = ChinaCoordinateConverter.wgs84ToGcj02(item.point);
      final selected = _selectedSearchResult?.id == item.id;
      final marker = Marker(
        position: LatLng(point.latitude, point.longitude),
        infoWindow: InfoWindow(title: item.name),
        icon: selected ? icons.selectedSearch : icons.search,
        anchor: const Offset(.5, .92),
        onTap: (_) => _selectSearchResult(item),
        zIndex: selected ? 3 : 1,
      )..setIdForCopy('search:${item.id}');
      result.add(marker);
    }
    return result;
  }

  void _selectPlace(NearbyPlace place) {
    _searchFocus.unfocus();
    _lastMediaResolved = null;
    setState(() {
      _selectedPlace = place;
      _selectedSearchResult = null;
      _panelFraction = .68;
    });
    _focusPoint(place.point);
  }

  void _selectSearchResult(LocationSearchResult item) {
    _searchFocus.unfocus();
    _lastMediaResolved = null;
    setState(() {
      _selectedSearchResult = item;
      _selectedPlace = null;
      _panelFraction = .5;
    });
    _focusPoint(item.point);
  }

  void _resolveSelectedMediaLayout(bool hasMedia) {
    if (!mounted || (_selectedPlace == null && _selectedSearchResult == null)) {
      return;
    }
    // Avoid redundant setState when the resolved state hasn't changed.
    if (_lastMediaResolved == hasMedia) return;
    _lastMediaResolved = hasMedia;
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
    _setIgnoreNextCameraMoveEnd();
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
      '&lat=${point.latitude}&lon=${point.longitude}'
      '&system=${point.coordinateSystem.name}',
    );
  }

  void _toggleSave(NearbyPlace place) {
    // SavedPlace has one canonical storage contract: WGS-84. Explore results
    // may still come from AMap in GCJ-02, so normalize before persisting.
    final point = place.point.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(place.point)
        : place.point;
    ref
        .read(userLibraryProvider.notifier)
        .togglePlace(
          SavedPlace(
            id: place.id,
            name: place.name,
            category: place.category.name,
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        );
  }

  /// Sets [_ignoreNextCameraMoveEnd] with a safety reset timer so the flag
  /// cannot remain stuck if the camera animation is interrupted by user touch.
  void _setIgnoreNextCameraMoveEnd() {
    _ignoreNextCameraMoveEnd = true;
    _ignoreCameraResetTimer?.cancel();
    _ignoreCameraResetTimer = Timer(const Duration(milliseconds: 700), () {
      _ignoreNextCameraMoveEnd = false;
    });
  }
}

class _V2SearchObject extends StatelessWidget {
  const _V2SearchObject({
    required this.controller,
    required this.focusNode,
    required this.onClose,
    required this.onClear,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
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
        prefixIcon: IconButton(
          onPressed: onClose,
          icon: const Icon(CupertinoIcons.chevron_left, color: V2Palette.ink),
        ),
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

class _V2SearchShortcutObject extends StatelessWidget {
  const _V2SearchShortcutObject({required this.onSelect});

  final ValueChanged<ExploreCreativeIntent> onSelect;

  static const _items = <(String, ExploreCreativeIntent)>[
    ('拍摄补给', ExploreCreativeIntent.supplies),
    ('停车场', ExploreCreativeIntent.parking),
    ('附近餐饮', ExploreCreativeIntent.food),
    ('加油站', ExploreCreativeIntent.fuel),
    ('附近医疗', ExploreCreativeIntent.medical),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: V2Palette.paper.withValues(alpha: .94),
    elevation: 14,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '快捷服务',
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              '搜索具体地点，或直接查看当前位置附近服务',
              style: TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, intent) in _items)
                      SizedBox(
                        width: itemWidth,
                        child: V2Pressable(
                          onTap: () => onSelect(intent),
                          compact: true,
                          color: V2Palette.canvas,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _intentIcon(intent.category),
                                  color: V2Palette.moss,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: V2Palette.ink,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _V2IntentStrip extends StatelessWidget {
  const _V2IntentStrip({
    required this.intent,
    required this.regionThemes,
    required this.onSelect,
    required this.onSelectRegionTheme,
  });

  final ExploreIntentState intent;
  final List<RegionPhotoTheme> regionThemes;
  final ValueChanged<ExploreCreativeIntent> onSelect;
  final ValueChanged<RegionPhotoTheme> onSelectRegionTheme;

  @override
  Widget build(BuildContext context) {
    final hasListedSelection = ExploreCreativeIntent.values.any(
      (item) => item.category == intent.category,
    );
    final hasContextSelection =
        intent.activeFocus != null ||
        (intent.regionTheme == null && !hasListedSelection);
    final chips = <Widget>[
      if (hasContextSelection)
        _V2ThemeChip(
          key: const Key('v2-explore-theme-context'),
          label: _categoryTitle(intent.category),
          category: intent.category,
          selected: true,
        ),
      for (final item in ExploreCreativeIntent.values)
        _V2ThemeChip(
          key: Key('v2-explore-theme-${item.name}'),
          label: item.label,
          category: item.category,
          selected:
              intent.activeFocus == null &&
              intent.regionTheme == null &&
              intent.category == item.category,
          onTap: () => onSelect(item),
        ),
      for (final theme in regionThemes)
        _V2ThemeChip(
          key: Key('v2-explore-region-theme-${theme.id}'),
          label: theme.label,
          category: categoryForExploreRegionTheme(theme),
          selected: intent.regionTheme?.id == theme.id,
          onTap: () => onSelectRegionTheme(theme),
        ),
    ];
    return SizedBox(
      key: const Key('v2-explore-theme-strip'),
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }
}

class _V2ThemeChip extends StatelessWidget {
  const _V2ThemeChip({
    super.key,
    required this.label,
    required this.category,
    required this.selected,
    this.onTap,
  });

  final String label;
  final NearbyPlaceCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: selected,
    label: '探索主题：$label',
    child: Material(
      color: selected ? V2Palette.mossSoft : V2Palette.paper,
      elevation: selected ? 7 : 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? V2Palette.moss : V2Palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _intentIcon(category),
                color: selected ? V2Palette.moss : V2Palette.mutedInk,
                size: 14,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? V2Palette.moss : V2Palette.ink,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _V2MapControlButton extends StatelessWidget {
  const _V2MapControlButton({
    super.key,
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
    required this.bottomContentInset,
    required this.regionLabel,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onToggle,
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
  final double bottomContentInset;
  final String regionLabel;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
  final VoidCallback onToggle;
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
    final selectedMedia = selectedPlace != null
        ? ref.watch(verifiedPlaceMediaProvider(selectedPlace!))
        : selectedSearchResult != null
        ? ref.watch(verifiedSearchResultMediaProvider(selectedSearchResult!))
        : null;
    if (selectedMedia != null && !selectedMedia.isLoading) {
      final media = selectedMedia.asData?.value ?? const <NearbyPlaceMedia>[];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onMediaResolved(media.isNotEmpty);
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
      _ => searchResults == null ? '$regionLabel · 附近发现' : '搜索结果',
    };
    final headerTitle = selectedPlace != null
        ? candidateMode
              ? '候选详情'
              : '地点详情'
        : selectedSearchResult != null
        ? '地点详情'
        : defaultTitle;
    if (!expanded) {
      return Material(
        color: Colors.transparent,
        elevation: 16,
        shadowColor: Colors.black26,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: V2Palette.paper.withValues(alpha: .88),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: .82)),
              ),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  onVerticalDragStart: (_) => onDragStart(),
                  onVerticalDragUpdate: (details) =>
                      onDragUpdate(details.delta.dy),
                  onVerticalDragEnd: onDragEnd,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
                    child: Column(
                      children: [
                        const V2GrabHandle(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                headerTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: V2Palette.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (candidateCount != null) ...[
                              Text(
                                '$candidateCount 处',
                                style: const TextStyle(
                                  color: V2Palette.moss,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            const Text(
                              '上拉查看',
                              style: TextStyle(
                                color: V2Palette.mutedInk,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      elevation: 16,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: V2Palette.paper.withValues(alpha: .88),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .82)),
            ),
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                onVerticalDragStart: (_) => onDragStart(),
                onVerticalDragUpdate: (details) =>
                    onDragUpdate(details.delta.dy),
                onVerticalDragEnd: onDragEnd,
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
                          const Text(
                            '下拉收起',
                            style: TextStyle(
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
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomContentInset),
                  child: _body(
                    context,
                    library,
                    candidateMode: candidateMode,
                    candidateCount: candidateCount ?? 0,
                    mediaHeaders: mediaHeaders,
                    selectedMedia: selectedMedia,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    UserLibraryState? library, {
    required bool candidateMode,
    required int candidateCount,
    required Map<String, String>? mediaHeaders,
    required AsyncValue<List<NearbyPlaceMedia>>? selectedMedia,
  }) {
    final selected = selectedPlace;
    if (selected != null) {
      final verifiedMedia =
          selectedMedia?.asData?.value ?? const <NearbyPlaceMedia>[];
      final resolvedMedia = selectedMedia == null || selectedMedia.isLoading
          ? const <NearbyPlaceMedia>[]
          : verifiedMedia;
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
        mediaLoading: selectedMedia?.isLoading == true,
        mediaHeaders: mediaHeaders,
      );
    }
    final searched = selectedSearchResult;
    if (searched != null) {
      final verifiedMedia =
          selectedMedia?.asData?.value ?? const <NearbyPlaceMedia>[];
      return _V2SelectedPlace(
        name: searched.name,
        detail: [
          if (searched.address?.isNotEmpty == true) searched.address!,
          if (searched.distanceMeters != null)
            _distance(searched.distanceMeters!),
        ].join(' · '),
        onRoute: () => onRoute(searched.name, searched.point),
        media: verifiedMedia,
        mediaLoading: selectedMedia?.isLoading == true,
        mediaHeaders: mediaHeaders,
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
          emptyLabel: '没有匹配地点，试试地点全名或加上城市名',
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
          return _V2NoNearbyResults(
            category: category,
            regionLabel: regionLabel,
            onSearchArea: onSearchMapArea,
          );
        }
        // The result panel can be deliberately collapsed almost to its handle
        // while the bottom navigation remains visible. Keep every header and
        // result in one scrollable viewport; a Column with an inner Expanded
        // list had no remaining height in that state and painted Flutter's
        // yellow/black overflow stripe above the dock.
        return _V2ResultList<NearbyPlace>(
          items: items,
          title: (item) => item.name,
          detail: (item) => candidateMode
              ? '候选 · ${_candidateDetail(item)}'
              : _placeDetail(item),
          onTap: onPlace,
          rankedCandidates: candidateMode,
          header: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: _ExploreDiscoveryLead(
                regionLabel: regionLabel,
                category: category,
              ),
            ),
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
          ],
        );
      },
    );
  }

  static String _placeDetail(NearbyPlace place) => [
    _distance(place.distanceMeters),
    if (place.address?.isNotEmpty == true) place.address!,
    if (place.sourceEvidenceCount > 0) '公开资料${place.sourceEvidenceCount}条',
    if (place.aiDiscovered) '资料发现',
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
  const _V2NoNearbyResults({
    required this.category,
    required this.regionLabel,
    required this.onSearchArea,
  });

  final NearbyPlaceCategory category;
  final String regionLabel;
  final VoidCallback onSearchArea;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          decoration: BoxDecoration(
            color: V2Palette.canvas,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: V2Palette.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: V2Palette.mossSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(_intentIcon(category), color: V2Palette.moss),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$regionLabel还没有${_categoryTitle(category)}',
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '这只说明当前主题的地点与资料线索不足，不等于这里没有值得看的内容。',
                      style: TextStyle(
                        color: V2Palette.mutedInk,
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: V2Pressable(
                onTap: onSearchArea,
                compact: true,
                color: V2Palette.mossSoft,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 11),
                  child: Center(
                    child: Text(
                      '搜索此区域',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
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

class _ExploreDiscoveryLead extends StatelessWidget {
  const _ExploreDiscoveryLead({
    required this.regionLabel,
    required this.category,
  });

  final String regionLabel;
  final NearbyPlaceCategory category;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
    decoration: BoxDecoration(
      color: V2Palette.canvas,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: V2Palette.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                regionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_categoryTitle(category)}  ·  附近发现',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _V2ResultList<T> extends StatelessWidget {
  const _V2ResultList({
    required this.items,
    required this.title,
    required this.detail,
    required this.onTap,
    this.header = const [],
    this.rankedCandidates = false,
    this.emptyLabel = '这个范围暂无线索',
  });
  final List<T> items;
  final String Function(T) title;
  final String Function(T) detail;
  final ValueChanged<T> onTap;
  final List<Widget> header;
  final bool rankedCandidates;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 22),
      children: [
        ...header,
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            child: Center(child: Text(emptyLabel)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index += 1) ...[
                  if (index > 0) const Divider(height: 1),
                  _V2ResultListItem<T>(
                    item: items[index],
                    index: index,
                    title: title,
                    detail: detail,
                    onTap: onTap,
                    rankedCandidates: rankedCandidates,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _V2ResultListItem<T> extends StatelessWidget {
  const _V2ResultListItem({
    required this.item,
    required this.index,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.rankedCandidates,
  });

  final T item;
  final int index;
  final String Function(T) title;
  final String Function(T) detail;
  final ValueChanged<T> onTap;
  final bool rankedCandidates;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(item),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          if (rankedCandidates)
            _V2CandidateRankBadge(rank: index + 1)
          else
            const Icon(CupertinoIcons.location_solid, color: V2Palette.moss),
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
    this.media = const [],
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
  final List<NearbyPlaceMedia> media;
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
          child: switch ((mediaLoading, media.isNotEmpty)) {
            (_, true) => _V2PlaceDetailGallery(
              key: ValueKey(media.first.id),
              media: media,
              headers: mediaHeaders,
            ),
            (true, _) => const _V2PlacePhotoLoading(),
            _ => const SizedBox.shrink(),
          },
        ),
        SizedBox(height: media.isNotEmpty || mediaLoading ? 16 : 8),
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

class _V2PlaceDetailGallery extends StatefulWidget {
  const _V2PlaceDetailGallery({
    required this.media,
    required this.headers,
    super.key,
  });

  final List<NearbyPlaceMedia> media;
  final Map<String, String>? headers;

  @override
  State<_V2PlaceDetailGallery> createState() => _V2PlaceDetailGalleryState();
}

class _V2PlaceDetailGalleryState extends State<_V2PlaceDetailGallery> {
  var _index = 0;

  @override
  void didUpdateWidget(covariant _V2PlaceDetailGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.media.length) _index = 0;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 156,
    child: Stack(
      children: [
        PageView.builder(
          itemCount: widget.media.length,
          onPageChanged: (value) => setState(() => _index = value),
          itemBuilder: (context, index) => _V2PlaceDetailPhoto(
            media: widget.media[index],
            headers: widget.headers,
          ),
        ),
        if (widget.media.length > 1)
          Positioned(
            top: 9,
            right: 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .58),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  '${_index + 1}/${widget.media.length}',
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
  );
}

class _V2PlaceDetailPhoto extends StatefulWidget {
  const _V2PlaceDetailPhoto({required this.media, required this.headers});

  final NearbyPlaceMedia media;
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
      setState(() => _failed = true);
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
                      'wikidataEntity' => '已按 Wikidata 实体核对',
                      'amapPoiId' => '已按高德 POI 绑定',
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
                    _activeMedia.sourceTier == 'supplemental'
                        ? '同 POI 附图 · ${_activeMedia.attribution}'
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
