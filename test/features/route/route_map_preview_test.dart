import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/presentation/route_map_preview.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';

import '../explore/map_consent_test_harness.dart';

void main() {
  testWidgets('requires the shared AMap consent before building route map', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway();
    final container = createMapTestContainer(
      amapKey: 'test-key',
      gateway: gateway,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: RouteMapPreview(
              route: _route(),
              mapBuilder: (_) => const SizedBox(key: Key('route-map-surface')),
            ),
          ),
        ),
      ),
    );

    expect(find.text('同意并显示路线地图'), findsOneWidget);
    expect(find.byKey(const Key('route-map-surface')), findsNothing);

    await tester.tap(find.text('同意并显示路线地图'));
    await tester.pump();

    expect(find.byKey(const Key('route-map-surface')), findsOneWidget);
    expect(gateway.initialized, isTrue);
  });

  testWidgets('route points missing uses a stable text fallback', (
    tester,
  ) async {
    final route = DrivingRoute(
      destinationName: '无折线路线',
      distanceMeters: 100,
      durationSeconds: 60,
      tollsYuan: 0,
      polyline: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: RouteMapPreview(route: route)),
        ),
      ),
    );

    expect(find.textContaining('路线点不足'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('route markers avoid asset-backed icons on Android', (
    tester,
  ) async {
    final container = createMapTestContainer(amapKey: 'test-key');
    container.read(mapConsentControllerProvider.notifier).grantConsent();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: RouteMapPreview(route: _route())),
        ),
      ),
    );

    final map = tester.widget<AMapWidget>(find.byType(AMapWidget));
    expect(map.markers, hasLength(2));
    expect(tester.getSize(find.byType(AMapWidget)).height, 220);
    expect(
      map.markers.every(
        (marker) => marker.icon == BitmapDescriptor.defaultMarker,
      ),
      isTrue,
    );
  });

  testWidgets('explains map creation and a slow platform view', (tester) async {
    final container = createMapTestContainer(amapKey: 'test-key');
    addTearDown(container.dispose);
    container.read(mapConsentControllerProvider.notifier).grantConsent();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: RouteMapPreview(route: _route())),
        ),
      ),
    );

    final loading = find.byKey(const Key('route-map-loading'));
    expect(loading, findsOneWidget);
    expect(find.text('正在绘制路线地图'), findsOneWidget);
    expect(tester.getSize(loading).height, 220);

    await tester.pump(const Duration(seconds: 8));
    expect(find.text('地图加载较慢，可先查看文字路线'), findsOneWidget);
  });

  testWidgets('renders imported GPX segments as separate polylines', (
    tester,
  ) async {
    final container = createMapTestContainer(amapKey: 'test-key');
    addTearDown(container.dispose);
    container.read(mapConsentControllerProvider.notifier).grantConsent();
    final route = DrivingRoute(
      destinationName: '分段轨迹',
      distanceMeters: 500,
      durationSeconds: 600,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.01, longitude: 120.01),
        GeoPoint(latitude: 31, longitude: 121),
        GeoPoint(latitude: 31.01, longitude: 121.01),
      ],
      polylineSegmentBreakIndexes: const [2],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: RouteMapPreview(route: route)),
        ),
      ),
    );

    final map = tester.widget<AMapWidget>(find.byType(AMapWidget));
    expect(map.polylines, hasLength(2));
    expect(map.polylines.every((line) => line.points.length == 2), isTrue);
  });
}

DrivingRoute _route() => DrivingRoute(
  destinationName: '湖岸机位',
  distanceMeters: 5000,
  durationSeconds: 900,
  tollsYuan: 0,
  polyline: const [
    GeoPoint(
      latitude: 31.23,
      longitude: 121.47,
      coordinateSystem: CoordinateSystem.gcj02,
    ),
    GeoPoint(
      latitude: 31.24,
      longitude: 121.50,
      coordinateSystem: CoordinateSystem.gcj02,
    ),
  ],
);
