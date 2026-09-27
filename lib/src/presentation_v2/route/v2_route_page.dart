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
import 'package:luma_nest/src/core/location/geo_distance.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/active_shooting_intent.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/application/route_navigation_launcher.dart';
import 'package:luma_nest/src/features/route/application/route_scout_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_scout_plan.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:x_amap_base/x_amap_base.dart';

part 'widgets/v2_route_verdict.dart';
part 'widgets/v2_route_action_object.dart';
part 'widgets/v2_route_scout_sheet.dart';
part 'widgets/v2_route_scout_timeline.dart';

class V2RoutePage extends ConsumerWidget {
  const V2RoutePage({
    super.key,
    this.destinationName,
    this.destinationLatitude,
    this.destinationLongitude,
    this.destinationCoordinateSystem = CoordinateSystem.wgs84,
    this.travelMode = RouteTravelMode.driving,
    this.activeShootingIntent,
  });

  final String? destinationName;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final CoordinateSystem destinationCoordinateSystem;
  final RouteTravelMode travelMode;
  final ActiveShootingIntent? activeShootingIntent;

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
    final coordinateSystem =
        destinationLatitude != null && destinationLongitude != null
        ? destinationCoordinateSystem
        : CoordinateSystem.wgs84;
    final rawPoint = GeoPoint(
      latitude: latitude,
      longitude: longitude,
      coordinateSystem: coordinateSystem,
    );
    final destination = RouteDestination(
      name: name,
      // Route, target and weather contracts use WGS-84. Explore carries the
      // coordinate system explicitly so AMap GCJ-02 values are converted once.
      point: ChinaCoordinateConverter.gcj02ToWgs84(rawPoint),
      travelMode: travelMode,
    );
    return _V2RouteStage(
      destination: destination,
      activeShootingIntent: activeShootingIntent,
    );
  }
}

class _V2RouteStage extends ConsumerStatefulWidget {
  const _V2RouteStage({required this.destination, this.activeShootingIntent});
  final RouteDestination destination;
  final ActiveShootingIntent? activeShootingIntent;

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
      data: (value) => _V2LiveRoute(
        route: value,
        destination: widget.destination,
        activeShootingIntent: widget.activeShootingIntent,
      ),
    );
  }
}

class _V2LiveRoute extends ConsumerStatefulWidget {
  const _V2LiveRoute({
    required this.route,
    required this.destination,
    this.activeShootingIntent,
  });
  final DrivingRoute route;
  final RouteDestination destination;
  final ActiveShootingIntent? activeShootingIntent;

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
    // Keep the latest route deadline in the foreground scope so leaving the
    // route page does not silently downgrade an already scheduled reminder.
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
    final scout = ref.watch(routeScoutPlanProvider(_scoutRequest));
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
      _syncDeparturePlan(snapshot);
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
                    width: 10,
                    color: V2Palette.ink,
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
          child: V2RouteVerdict(
            route: widget.route,
            destination: widget.destination,
            snapshot: snapshot,
            scout: scout.asData?.value,
            activeShootingIntent: widget.activeShootingIntent,
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: MediaQuery.paddingOf(context).bottom + 80,
          child: _V2RouteActionObject(
            scout: scout,
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

  void _syncDeparturePlan(ContextSnapshot? snapshot) {
    final intent = widget.activeShootingIntent;
    if (intent == null || snapshot == null) return;
    final now = DateTime.now().toUtc();
    if (snapshot.isStale ||
        snapshot.dataFreshness == ContextDataFreshness.stale ||
        !snapshot.expiresAt.toUtc().isAfter(now)) {
      // A stale snapshot cannot create or replace a departure plan. Preserve
      // any already scheduled reminder until a fresh reconciliation decides
      // whether it remains valid.
      return;
    }
    final session = snapshot.shootingSessions
        .where((candidate) => candidate.id == intent.sessionId)
        .firstOrNull;
    final target = session?.targetCandidates
        .where((candidate) => candidate.id == intent.targetId)
        .firstOrNull;
    if (session == null ||
        target == null ||
        GeoDistance.metersBetween(
              ChinaCoordinateConverter.gcj02ToWgs84(target.coordinate),
              widget.destination.point,
            ) >
            target.arrivalRadiusMeters) {
      ref
          .read(shootingDeparturePlanProvider.notifier)
          .clearFor(intent.sessionId, targetId: intent.targetId);
      return;
    }
    final decision = ShootingExecutionResolver.resolve(
      session: session,
      now: DateTime.now(),
      target: target,
      routeDuration: Duration(seconds: widget.route.durationSeconds),
    );
    final deadline = decision.departureDeadline;
    if (deadline == null) {
      ref
          .read(shootingDeparturePlanProvider.notifier)
          .clearFor(intent.sessionId, targetId: intent.targetId);
      return;
    }
    ref
        .read(shootingDeparturePlanProvider.notifier)
        .setPlan(
          ShootingDeparturePlan(
            sessionId: intent.sessionId,
            targetId: intent.targetId,
            departureDeadline: deadline,
            routeDuration: Duration(seconds: widget.route.durationSeconds),
            createdAt: intent.createdAt,
          ),
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

  /// Keep the bounded, transient corridor alongside the route presentation.
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
}
