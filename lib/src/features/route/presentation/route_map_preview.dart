import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:x_amap_base/x_amap_base.dart';

typedef RouteMapBuilder = Widget Function(DrivingRoute route);

class RouteMapPreview extends ConsumerWidget {
  const RouteMapPreview({super.key, required this.route, this.mapBuilder});

  final DrivingRoute route;
  final RouteMapBuilder? mapBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (route.polyline.length < 2) {
      return const _MapMessage(
        icon: Icons.map_outlined,
        message: '路线点不足，暂时无法绘制地图概览',
      );
    }
    final consent = ref.watch(mapConsentControllerProvider);
    return switch (consent) {
      MapConsentConfigurationMissing() => const _MapMessage(
        icon: Icons.map_outlined,
        message: '路线地图尚未配置，文字路线仍可使用',
      ),
      MapConsentAwaiting() => _MapConsentPrompt(
        onAccept: () =>
            ref.read(mapConsentControllerProvider.notifier).grantConsent(),
      ),
      MapConsentReady() => _ReadyRouteMap(
        route: route,
        mapBuilder: mapBuilder,
        onInitialize: (context) => ref
            .read(mapConsentControllerProvider.notifier)
            .ensureInitialized(context),
      ),
    };
  }
}

class _ReadyRouteMap extends StatefulWidget {
  const _ReadyRouteMap({
    required this.route,
    required this.mapBuilder,
    required this.onInitialize,
  });

  final DrivingRoute route;
  final RouteMapBuilder? mapBuilder;
  final ValueChanged<BuildContext> onInitialize;

  @override
  State<_ReadyRouteMap> createState() => _ReadyRouteMapState();
}

class _ReadyRouteMapState extends State<_ReadyRouteMap> {
  Timer? _slowTimer;
  Timer? _settleTimer;
  var _platformCreated = false;
  var _mapCreated = false;
  var _loadingSlowly = false;

  @override
  void initState() {
    super.initState();
    widget.onInitialize(context);
    _armLoadingState();
  }

  @override
  void didUpdateWidget(covariant _ReadyRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route.sourceId != widget.route.sourceId ||
        oldWidget.route.destinationName != widget.route.destinationName ||
        oldWidget.route.travelMode != widget.route.travelMode) {
      _armLoadingState();
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }

  void _armLoadingState() {
    _slowTimer?.cancel();
    _settleTimer?.cancel();
    _platformCreated = false;
    _mapCreated = false;
    _loadingSlowly = false;
    _slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_mapCreated) setState(() => _loadingSlowly = true);
    });
  }

  void _onMapCreated(AMapController controller, LatLngBounds bounds) {
    _platformCreated = true;
    unawaited(
      controller.moveCamera(
        CameraUpdate.newLatLngBounds(bounds, 48),
        animated: false,
      ),
    );
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(seconds: 6), _markMapReady);
  }

  void _onCameraMoveEnd() {
    if (!_platformCreated || _mapCreated) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 450), _markMapReady);
  }

  void _markMapReady() {
    _slowTimer?.cancel();
    _settleTimer?.cancel();
    if (mounted && !_mapCreated) setState(() => _mapCreated = true);
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.mapBuilder;
    if (builder != null) return builder(widget.route);

    final points = widget.route.polyline.map(_toLatLng).toList(growable: false);
    final segments = _splitSegments(
      points,
      widget.route.polylineSegmentBreakIndexes,
    );
    final start = points.first;
    final end = points.last;
    final bounds = _bounds(points);
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AMapWidget(
              initialCameraPosition: CameraPosition(
                target: points[points.length ~/ 2],
                zoom: 10,
              ),
              compassEnabled: true,
              scaleEnabled: true,
              markers: {
                Marker(
                  position: start,
                  infoWindow: const InfoWindow(title: '起点'),
                ),
                Marker(
                  position: end,
                  infoWindow: InfoWindow(title: widget.route.destinationName),
                ),
              },
              polylines: {
                for (final segment in segments)
                  if (segment.length >= 2)
                    Polyline(
                      points: segment,
                      width: 6,
                      color: Theme.of(context).colorScheme.primary,
                      capType: CapType.round,
                      joinType: JoinType.round,
                    ),
              },
              onMapCreated: (controller) {
                _onMapCreated(controller, bounds);
              },
              onCameraMoveEnd: (_) => _onCameraMoveEnd(),
            ),
            if (!_mapCreated)
              Positioned.fill(
                child: _RouteMapLoadingOverlay(slow: _loadingSlowly),
              ),
            if (widget.route.isStale)
              const Positioned(
                left: 10,
                right: 10,
                top: 10,
                child: _OfflineMapLabel(),
              ),
          ],
        ),
      ),
    );
  }

  LatLng _toLatLng(GeoPoint point) {
    final gcj02 = point.coordinateSystem == CoordinateSystem.wgs84
        ? ChinaCoordinateConverter.wgs84ToGcj02(point)
        : point;
    return LatLng(gcj02.latitude, gcj02.longitude);
  }

  LatLngBounds _bounds(List<LatLng> points) {
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = mathMin(minLatitude, point.latitude);
      maxLatitude = mathMax(maxLatitude, point.latitude);
      minLongitude = mathMin(minLongitude, point.longitude);
      maxLongitude = mathMax(maxLongitude, point.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLatitude, minLongitude),
      northeast: LatLng(maxLatitude, maxLongitude),
    );
  }

  List<List<LatLng>> _splitSegments(List<LatLng> points, List<int> breaks) {
    final starts = <int>[
      0,
      ...breaks.where((index) => index > 0 && index < points.length),
    ];
    starts.sort();
    return List.generate(starts.length, (index) {
      final end = index + 1 < starts.length ? starts[index + 1] : points.length;
      return points.sublist(starts[index], end);
    }, growable: false);
  }

  double mathMin(double first, double second) =>
      first < second ? first : second;

  double mathMax(double first, double second) =>
      first > second ? first : second;
}

class _RouteMapLoadingOverlay extends StatelessWidget {
  const _RouteMapLoadingOverlay({required this.slow});

  final bool slow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = slow ? '地图加载较慢，可先查看文字路线' : '正在绘制路线地图';
    return Semantics(
      key: const Key('route-map-loading'),
      liveRegion: true,
      label: message,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (slow)
                  Icon(
                    Icons.map_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                else
                  const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _MapConsentPrompt extends StatelessWidget {
  const _MapConsentPrompt({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => _MapFrame(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.map_outlined),
        const SizedBox(height: 8),
        const Text('显示路线地图前需要同意高德地图隐私政策'),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onAccept, child: const Text('同意并显示路线地图')),
      ],
    ),
  );
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => _MapFrame(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(icon), const SizedBox(height: 8), Text(message)],
    ),
  );
}

class _MapFrame extends StatelessWidget {
  const _MapFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

class _OfflineMapLabel extends StatelessWidget {
  const _OfflineMapLabel();

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
    borderRadius: BorderRadius.circular(12),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text('离线路线：底图可能不可用，请勿用于逐向导航'),
    ),
  );
}
