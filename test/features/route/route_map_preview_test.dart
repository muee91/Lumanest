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
