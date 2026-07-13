import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/presentation/route_page.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';

void main() {
  testWidgets('labels cached routes and explains their limitation', (
    tester,
  ) async {
    final route = DrivingRoute(
      destinationName: '缓存机位',
      distanceMeters: 5000,
      durationSeconds: 900,
      tollsYuan: 0,
      polyline: const [],
      isStale: true,
      cachedAt: DateTime.utc(2026, 7, 13),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RoutePage(
              destinationName: '缓存机位',
              destinationLatitude: 31,
              destinationLongitude: 121,
              routeAsync: AsyncData(route),
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在显示离线路线'), findsOneWidget);
    expect(find.textContaining('请勿将缓存结果用于逐向导航'), findsOneWidget);
  });

  testWidgets('shows an honest action timeline and separate current safety', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 7, 13, 10);
    final route = DrivingRoute(
      destinationName: '湖岸机位',
      distanceMeters: 5000,
      durationSeconds: const Duration(hours: 2).inSeconds,
      tollsYuan: 0,
      polyline: const [],
    );
    final snapshot = ContextSnapshot(
      id: 'route-context',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.lake,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: true,
      safetyEventIds: const ['strong-wind'],
      sunrise: now.subtract(const Duration(hours: 8)),
      sunset: now.add(const Duration(minutes: 50)),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RoutePage(
              destinationName: '湖岸机位',
              destinationLatitude: 31,
              destinationLongitude: 121,
              routeAsync: AsyncData(route),
              contextSnapshot: snapshot,
              timelineNow: now,
            ),
          ),
        ),
      ),
    );

    expect(find.text('当前风力较强'), findsOneWidget);
    expect(find.text('行动时间轴'), findsOneWidget);
    expect(find.text('落日窗口'), findsOneWidget);
    expect(find.text('蓝调窗口'), findsOneWidget);
    expect(find.textContaining('未包含沿途地形遮挡和未来天气变化'), findsOneWidget);
  });

  testWidgets('walking route shows ascent honesty and return-light warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 7, 13, 10);
    final route = DrivingRoute(
      destinationName: '徒步机位',
      distanceMeters: 3000,
      durationSeconds: const Duration(hours: 1).inSeconds,
      tollsYuan: 0,
      polyline: const [],
      travelMode: RouteTravelMode.walking,
    );
    final snapshot = ContextSnapshot(
      id: 'hiking-context',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.hiking,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: true,
      sunset: now.add(const Duration(minutes: 90)),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RoutePage(
              destinationName: '徒步机位',
              destinationLatitude: 31,
              destinationLongitude: 121,
              routeAsync: AsyncData(route),
              contextSnapshot: snapshot,
              timelineNow: now,
              travelMode: RouteTravelMode.walking,
            ),
          ),
        ),
      ),
    );

    expect(find.text('徒步'), findsOneWidget);
    expect(find.text('累计爬升'), findsOneWidget);
    expect(find.text('暂无高程'), findsOneWidget);
    expect(find.text('徒步返程参考'), findsOneWidget);
    expect(find.textContaining('可能晚于日落'), findsOneWidget);
    expect(find.text('扫描沿途补给'), findsOneWidget);
  });

  testWidgets('walking route displays sampled elevation with attribution', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final route = DrivingRoute(
      destinationName: '山地机位',
      distanceMeters: 3000,
      durationSeconds: 1800,
      tollsYuan: 0,
      polyline: const [],
      travelMode: RouteTravelMode.walking,
      ascentMeters: 128,
      descentMeters: 64,
      elevationSource: 'Open-Meteo Elevation API',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RoutePage(
              destinationName: '山地机位',
              destinationLatitude: 31,
              destinationLongitude: 121,
              routeAsync: AsyncData(route),
              travelMode: RouteTravelMode.walking,
            ),
          ),
        ),
      ),
    );

    expect(find.text('128 m'), findsOneWidget);
    expect(find.textContaining('高程来源：Open-Meteo'), findsOneWidget);
    expect(find.textContaining('不替代专业测绘'), findsOneWidget);
  });
}
