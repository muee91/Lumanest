import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/application/route_navigation_launcher.dart';
import 'package:luma_nest/src/features/route/application/route_scout_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_scout_plan.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:x_amap_base/x_amap_base.dart';

class V2RoutePage extends ConsumerWidget {
  const V2RoutePage({
    super.key,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
    this.travelMode = RouteTravelMode.driving,
  });

  final String? destinationName;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final RouteTravelMode travelMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    final recent = library?.recentRoute;
    final name = destinationName ?? recent?.name;
    final latitude = destinationLatitude ?? recent?.latitude;
    final longitude = destinationLongitude ?? recent?.longitude;
    if (name == null || latitude == null || longitude == null) {
      return V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.map_pin_ellipse,
          title: '先选一个要抵达的地方',
          detail: '路线页只保留行动信息；地点选择从地图开始。',
          action: '去地图选择',
          onAction: () => context.go('/explore'),
        ),
      );
    }
    final destination = RouteDestination(
      name: name,
      point: GeoPoint(latitude: latitude, longitude: longitude),
      travelMode: travelMode,
    );
    return _V2RouteStage(destination: destination);
  }
}

class _V2RouteStage extends ConsumerStatefulWidget {
  const _V2RouteStage({required this.destination});
  final RouteDestination destination;

  @override
  ConsumerState<_V2RouteStage> createState() => _V2RouteStageState();
}

class _V2RouteStageState extends ConsumerState<_V2RouteStage> {
  bool _mapInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mapInitialized) return;
    final consent = ref.read(mapConsentControllerProvider);
    if (consent is MapConsentReady) {
      _mapInitialized = true;
      ref
          .read(mapConsentControllerProvider.notifier)
          .ensureInitialized(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapConsent = ref.watch(mapConsentControllerProvider);
    if (mapConsent is MapConsentAwaiting) {
      return V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.hand_raised,
          title: '路线需要地图权限',
          detail: '同意高德地图隐私政策后才能计算真实路线。',
          action: '同意并继续',
          onAction: () =>
              ref.read(mapConsentControllerProvider.notifier).grantConsent(),
        ),
      );
    }
    if (mapConsent is MapConsentConfigurationMissing) {
      return V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.map,
          title: '路线服务尚未配置',
          detail: 'Android 地图密钥缺失，无法生成真实路线。',
          action: '回到探索',
          onAction: () => context.go('/explore'),
        ),
      );
    }
    if (!_mapInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _mapInitialized) return;
        final consent = ref.read(mapConsentControllerProvider);
        if (consent is! MapConsentReady) return;
        setState(() => _mapInitialized = true);
        ref
            .read(mapConsentControllerProvider.notifier)
            .ensureInitialized(context);
      });
    }
    final route = ref.watch(drivingRouteProvider(widget.destination));
    return route.when(
      loading: () => const ColoredBox(
        color: V2Palette.canvas,
        child: V2LoadingObject(label: '正在把路线变成行动计划'),
      ),
      error: (_, _) => V2PageStage(
        child: V2EmptyObject(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: '路线暂时没有生成',
          detail: '保留目的地，等网络恢复后再计算。',
          action: '重新计算',
          onAction: () =>
              ref.invalidate(drivingRouteProvider(widget.destination)),
        ),
      ),
      data: (value) =>
          _V2LiveRoute(route: value, destination: widget.destination),
    );
  }
}

class _V2LiveRoute extends ConsumerStatefulWidget {
  const _V2LiveRoute({required this.route, required this.destination});
  final DrivingRoute route;
  final RouteDestination destination;

  @override
  ConsumerState<_V2LiveRoute> createState() => _V2LiveRouteState();
}

class _V2LiveRouteState extends ConsumerState<_V2LiveRoute> {
  AMapController? _controller;
  bool _fitOnce = false;
  String? _syncedRouteRevision;

  @override
  void dispose() {
    _controller?.disponse();
    super.dispose();
  }

  SavedRouteDestination get _savedDestination => SavedRouteDestination(
    name: widget.destination.name,
    latitude: widget.destination.point.latitude,
    longitude: widget.destination.point.longitude,
    travelMode: widget.destination.travelMode.name,
  );

  String get _routeKey =>
      '${widget.destination.point.latitude.toStringAsFixed(6)}:'
      '${widget.destination.point.longitude.toStringAsFixed(6)}:'
      '${widget.destination.travelMode.name}';

  String get _routeRevision =>
      '$_routeKey:${widget.route.durationSeconds}:${widget.route.polyline.length}:'
      '${widget.route.sourceId ?? ''}';

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(environmentSnapshotProvider).asData?.value;
    final library = ref.watch(userLibraryProvider).asData?.value;
    final active =
        library?.activeJourney?.matches(
          _savedDestination,
          routeKey: _routeKey,
        ) ==
        true;
    final quietMode = active;
    final now = ref.watch(currentTimeProvider)();
    final scout = ref.watch(routeScoutPlanProvider(_scoutRequest));
    final activeJourney = active ? library?.activeJourney : null;
    final journeyProgress = activeJourney == null
        ? 0.0
        : RouteScoutPlan.progressForJourney(
            startedAt: activeJourney.startedAt,
            durationSeconds: widget.route.durationSeconds,
            now: now,
          );
    final nextScout = scout.asData?.value.nextAfter(journeyProgress);
    final points = widget.route.polyline
        .map(ChinaCoordinateConverter.wgs84ToGcj02)
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final destination = ChinaCoordinateConverter.wgs84ToGcj02(
      widget.destination.point,
    );
    final scoutMarkers = <Marker>{};
    for (final node in scout.asData?.value.nodes ?? const <RouteScoutNode>[]) {
      final place = node.place;
      if (place == null || scoutMarkers.length >= 6) continue;
      final point = place.point.coordinateSystem == CoordinateSystem.gcj02
          ? place.point
          : ChinaCoordinateConverter.wgs84ToGcj02(place.point);
      scoutMarkers.add(
        Marker(
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(title: place.name),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_syncedRouteRevision != _routeRevision) {
        _syncedRouteRevision = _routeRevision;
        _replaceCorridor(departureAt: DateTime.now());
        _syncPlannedRoute();
      }
      if (_fitOnce || _controller == null || points.isEmpty) return;
      _fitOnce = true;
      final bounds = LatLngBounds(
        southwest: LatLng(
          points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
          points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
        ),
        northeast: LatLng(
          points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
          points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
        ),
      );
      unawaited(
        _controller!.moveCamera(
          CameraUpdate.newLatLngBounds(bounds, 70),
          duration: 620,
        ),
      );
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        AMapWidget(
          initialCameraPosition: CameraPosition(
            target: LatLng(destination.latitude, destination.longitude),
            zoom: 12,
          ),
          onMapCreated: (value) {
            _controller = value;
            if (mounted) setState(() {});
          },
          myLocationStyleOptions: MyLocationStyleOptions(true),
          compassEnabled: false,
          scaleEnabled: false,
          polylines: points.isEmpty
              ? const <Polyline>{}
              : {
                  Polyline(
                    points: points,
                    width: quietMode ? 12 : 10,
                    color: quietMode ? V2Palette.moss : V2Palette.ink,
                    capType: CapType.round,
                    joinType: JoinType.round,
                  ),
                },
          markers: {
            Marker(
              position: LatLng(destination.latitude, destination.longitude),
              infoWindow: InfoWindow(title: widget.destination.name),
            ),
            ...scoutMarkers,
          },
        ),
        Positioned(
          left: 20,
          right: 20,
          top: MediaQuery.paddingOf(context).top + 12,
          child: _V2RouteVerdict(
            route: widget.route,
            snapshot: snapshot,
            scout: scout.asData?.value,
            quiet: quietMode,
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          left: 14,
          right: 14,
          bottom: MediaQuery.paddingOf(context).bottom + 80,
          height: quietMode ? 194 : 286,
          child: _V2RouteActionObject(
            route: widget.route,
            scout: scout,
            nextScout: nextScout,
            quiet: quietMode,
            active: active,
            nextInstruction: widget.route.instructions.firstOrNull,
            onStart: _start,
            onEnd: _end,
            onScout: _openScout,
            onNavigate: () => unawaited(_navigate()),
            onExplore: () => context.go('/explore'),
          ),
        ),
      ],
    );
  }

  RouteScoutRequest get _scoutRequest => RouteScoutRequest(
    route: widget.route,
    destination: widget.destination,
    routeKey: _routeKey,
  );

  void _openScout() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .86,
        child: _V2RouteScoutSheet(
          request: _scoutRequest,
          onNavigate: () {
            Navigator.of(sheetContext).pop();
            unawaited(_navigate());
          },
        ),
      ),
    );
  }

  Future<void> _navigate() async {
    final opened = await RouteNavigationLauncher.open(widget.destination);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法打开外部地图')));
    }
  }

  void _syncPlannedRoute() {
    final mode = widget.destination.travelMode == RouteTravelMode.walking
        ? ContextRouteMode.hiking
        : ContextRouteMode.driving;
    ref
        .read(routeContextStateProvider.notifier)
        .plan(
          mode,
          identity: RouteIdentity(
            latitude: widget.destination.point.latitude,
            longitude: widget.destination.point.longitude,
            mode: mode,
          ),
        );
    unawaited(
      ref.read(userLibraryProvider.notifier).saveRecentRoute(_savedDestination),
    );
  }

  /// Keep the bounded, transient corridor alongside the route lifecycle.
  /// It is deliberately reconstructed locally from the loaded route and never
  /// persisted: the environment request only needs three coarse arrival
  /// samples to align light and weather with this one route.
  void _replaceCorridor({required DateTime departureAt}) {
    final controller = ref.read(routeCorridorContextProvider.notifier);
    if (widget.route.polyline.length < 2 || widget.route.durationSeconds < 1) {
      controller.clear();
      return;
    }
    controller.replace(
      RouteCorridorContext.fromPolyline(
        polyline: widget.route.polyline,
        durationSeconds: widget.route.durationSeconds,
        departureAt: departureAt,
        routeSeed: _routeKey,
      ),
    );
  }

  Future<void> _start() async {
    try {
      await ref
          .read(userLibraryProvider.notifier)
          .startJourney(_savedDestination, routeKey: _routeKey);
      _replaceCorridor(departureAt: DateTime.now());
      ref.read(routeContextStateProvider.notifier).start();
    } on ActiveJourneyConflict {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先结束正在进行的另一条路线')));
    }
  }

  Future<void> _end() async {
    await ref
        .read(userLibraryProvider.notifier)
        .endJourney(_savedDestination, routeKey: _routeKey);
    ref.read(routeContextStateProvider.notifier).end();
  }
}

class _V2RouteVerdict extends StatelessWidget {
  const _V2RouteVerdict({
    required this.route,
    required this.snapshot,
    required this.scout,
    required this.quiet,
  });
  final DrivingRoute route;
  final ContextSnapshot? snapshot;
  final RouteScoutPlan? scout;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final arrival = DateTime.now().add(
      Duration(seconds: route.durationSeconds),
    );
    final session = snapshot == null
        ? null
        : ShootingSessionSelector.select(
            snapshot!.shootingSessions,
            now: DateTime.now(),
          );
    final canCatch = session == null || arrival.isBefore(session.endsAt);
    final headline = quiet
        ? '路线进行中'
        : scout?.headline ??
              (session == null
                  ? '路线已经准备好'
                  : canCatch
                  ? '按当前路线赶得上'
                  : '按当前路线已经赶不上');
    final urgent = (scout?.criticalCount ?? 0) > 0 || !canCatch;
    return Material(
      color: quiet ? V2Palette.night : V2Palette.paper,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 16),
        child: Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: quiet
                    ? V2Palette.moss
                    : urgent
                    ? V2Palette.ember
                    : V2Palette.moss,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: TextStyle(
                      color: quiet ? Colors.white : V2Palette.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_duration(route.durationSeconds)} · ${_distance(route.distanceMeters)}',
                    style: TextStyle(
                      color: quiet ? Colors.white70 : V2Palette.mutedInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _time(arrival),
              style: TextStyle(
                color: quiet ? Colors.white : V2Palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _duration(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes 分钟';
    return '${minutes ~/ 60}小时${minutes % 60}分';
  }

  static String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')} 抵达';
}

class _V2RouteActionObject extends StatelessWidget {
  const _V2RouteActionObject({
    required this.route,
    required this.scout,
    required this.nextScout,
    required this.quiet,
    required this.active,
    required this.nextInstruction,
    required this.onStart,
    required this.onEnd,
    required this.onScout,
    required this.onNavigate,
    required this.onExplore,
  });

  final DrivingRoute route;
  final AsyncValue<RouteScoutPlan> scout;
  final RouteScoutNode? nextScout;
  final bool quiet;
  final bool active;
  final String? nextInstruction;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onScout;
  final VoidCallback onNavigate;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final plan = scout.asData?.value;
    final headline = quiet
        ? (nextScout?.title ?? nextInstruction ?? '沿路线继续前行')
        : plan?.headline ?? (scout.isLoading ? '正在整理沿途信息' : '路线已准备好');
    final detail = quiet
        ? nextScout?.detail
        : plan == null
        ? '探路失败不会影响路线与外部导航。'
        : '${plan.criticalCount + plan.highCount} 条重点 · '
              '${plan.photographyCount} 个拍摄时间 · ${plan.supportCount} 个补给线索';
    return Material(
      color: quiet ? V2Palette.night : V2Palette.paper,
      elevation: 18,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, quiet ? 18 : 22, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  quiet ? '下一条重要节点' : '路线探路',
                  style: TextStyle(
                    color: quiet ? V2Palette.moss : V2Palette.moss,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (plan != null)
                  Text(
                    plan.coverage == RouteScoutCoverage.full ? '数据完整' : '部分数据',
                    style: TextStyle(
                      color: quiet ? Colors.white54 : V2Palette.mutedInk,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: quiet ? Colors.white : V2Palette.ink,
                fontSize: quiet ? 19 : 22,
                height: 1.15,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 7),
              Text(
                detail,
                maxLines: quiet ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: quiet ? Colors.white60 : V2Palette.mutedInk,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                V2RoundAction(
                  icon: CupertinoIcons.map,
                  label: '探路',
                  onTap: onScout,
                ),
                const SizedBox(width: 10),
                V2RoundAction(
                  icon: quiet
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.arrow_2_circlepath,
                  label: quiet ? '导航' : '换地点',
                  onTap: quiet ? onNavigate : onExplore,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: V2Pressable(
                    onTap: active ? onEnd : onStart,
                    color: quiet ? V2Palette.paper : V2Palette.moss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Text(
                        active ? '结束行程' : '开始行程',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: quiet ? V2Palette.ink : Colors.white,
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
      ),
    );
  }
}

class _V2RouteScoutSheet extends ConsumerWidget {
  const _V2RouteScoutSheet({required this.request, required this.onNavigate});

  final RouteScoutRequest request;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scout = ref.watch(routeScoutPlanProvider(request));
    return Material(
      color: V2Palette.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: V2Palette.mutedInk.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '路线探路',
                          style: TextStyle(
                            color: V2Palette.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.7,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '只展示会影响行动的沿途信息，不替代地图导航。',
                          style: TextStyle(
                            color: V2Palette.mutedInk,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
            ),
            Expanded(
              child: scout.when(
                loading: () =>
                    const Center(child: V2LoadingObject(label: '正在读取沿途天气与补给')),
                error: (_, _) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      '探路数据暂时不可用，路线和外部导航仍可正常使用。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: V2Palette.mutedInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                data: (plan) => _V2RouteScoutTimeline(plan: plan),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: V2Pressable(
                onTap: onNavigate,
                color: V2Palette.moss,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.location_fill, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        '打开高德地图导航',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
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

class _V2RouteScoutTimeline extends StatelessWidget {
  const _V2RouteScoutTimeline({required this.plan});

  final RouteScoutPlan plan;

  @override
  Widget build(BuildContext context) {
    if (plan.nodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            '沿途暂无需要额外打断行程的信息。',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: plan.nodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final node = plan.nodes[index];
        return Material(
          color: V2Palette.paper,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _nodeColor(node).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _nodeIcon(node.kind),
                    color: _nodeColor(node),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              node.title,
                              style: const TextStyle(
                                color: V2Palette.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(node.routeProgress * 100).round()}% · ${_time(node.expectedAt)}',
                            style: const TextStyle(
                              color: V2Palette.mutedInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        node.detail,
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${node.source}${node.isStale ? ' · 缓存' : ''}',
                        style: TextStyle(
                          color: _nodeColor(node).withValues(alpha: .8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static Color _nodeColor(RouteScoutNode node) => switch (node.priority) {
    RouteScoutPriority.critical => V2Palette.ember,
    RouteScoutPriority.high => V2Palette.ember,
    RouteScoutPriority.normal => V2Palette.moss,
  };

  static IconData _nodeIcon(RouteScoutNodeKind kind) => switch (kind) {
    RouteScoutNodeKind.safety => Icons.warning_amber_rounded,
    RouteScoutNodeKind.weather => Icons.cloud_outlined,
    RouteScoutNodeKind.photography => Icons.photo_camera_outlined,
    RouteScoutNodeKind.fuel => Icons.local_gas_station_outlined,
    RouteScoutNodeKind.supply => Icons.shopping_bag_outlined,
    RouteScoutNodeKind.food => Icons.restaurant_outlined,
    RouteScoutNodeKind.parking => Icons.local_parking_outlined,
    RouteScoutNodeKind.medical => Icons.medical_services_outlined,
    RouteScoutNodeKind.route => Icons.route_outlined,
  };
}
