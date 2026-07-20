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
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:x_amap_base/x_amap_base.dart';

class V2RoutePage extends ConsumerWidget {
  const V2RoutePage({
    super.key,
    this.routeId,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
    this.travelMode = RouteTravelMode.driving,
  });

  final String? destinationName;
  final String? routeId;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final RouteTravelMode travelMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider).asData?.value;
    final recent = library?.recentRoute;
    final saved = routeId == null
        ? null
        : library?.savedRoutes
              .where((route) => route.id == routeId)
              .firstOrNull;
    final savedDestination = saved?.destination;
    final name = destinationName ?? savedDestination?.name ?? recent?.name;
    final latitude =
        destinationLatitude ?? savedDestination?.latitude ?? recent?.latitude;
    final longitude =
        destinationLongitude ??
        savedDestination?.longitude ??
        recent?.longitude;
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
    final points = widget.route.polyline
        .map(ChinaCoordinateConverter.wgs84ToGcj02)
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final destination = ChinaCoordinateConverter.wgs84ToGcj02(
      widget.destination.point,
    );
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
          },
        ),
        Positioned(
          left: 20,
          right: 20,
          top: MediaQuery.paddingOf(context).top + 12,
          child: _V2RouteVerdict(
            route: widget.route,
            snapshot: snapshot,
            quiet: quietMode,
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          left: 14,
          right: 14,
          bottom: MediaQuery.paddingOf(context).bottom + 80,
          height: quietMode ? 150 : 246,
          child: _V2RouteActionObject(
            route: widget.route,
            quiet: quietMode,
            active: active,
            nextInstruction: widget.route.instructions.firstOrNull,
            onStart: _start,
            onEnd: _end,
            onExplore: () => context.go('/explore'),
          ),
        ),
      ],
    );
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
    required this.quiet,
  });
  final DrivingRoute route;
  final ContextSnapshot? snapshot;
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
        : session == null
        ? '路线已经准备好'
        : canCatch
        ? '按当前路线赶得上'
        : '按当前路线已经赶不上';
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
                    : canCatch
                    ? V2Palette.moss
                    : V2Palette.ember,
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
    required this.quiet,
    required this.active,
    required this.nextInstruction,
    required this.onStart,
    required this.onEnd,
    required this.onExplore,
  });
  final DrivingRoute route;
  final bool quiet;
  final bool active;
  final String? nextInstruction;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Material(
    color: quiet ? V2Palette.night : V2Palette.paper,
    elevation: 18,
    shadowColor: Colors.black38,
    borderRadius: BorderRadius.circular(32),
    child: Padding(
      padding: EdgeInsets.fromLTRB(22, quiet ? 18 : 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!quiet) ...[
            const Text(
              '下一件事',
              style: TextStyle(
                color: V2Palette.moss,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            quiet ? (nextInstruction ?? '沿路线继续前行') : '确认器材，然后开始行程',
            maxLines: quiet ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: quiet ? Colors.white : V2Palette.ink,
              fontSize: quiet ? 20 : 22,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -.6,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              if (!quiet) ...[
                V2RoundAction(
                  icon: CupertinoIcons.arrow_2_circlepath,
                  label: '换目的地',
                  onTap: onExplore,
                ),
                const SizedBox(width: 12),
              ],
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
