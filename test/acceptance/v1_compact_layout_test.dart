import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/explore/presentation/explore_page.dart';
import 'package:luma_nest/src/features/inspiration/presentation/inspiration_page.dart';
import 'package:luma_nest/src/features/profile/presentation/profile_page.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/presentation/route_page.dart';
import 'package:luma_nest/src/features/today/presentation/today_page.dart';

void main() {
  testWidgets('今日在紧凑屏幕完整滚动且不溢出', (tester) async {
    _useCompactView(tester);
    final snapshot = ContextFixtures.desertDusk();
    await tester.pumpWidget(
      MaterialApp(
        theme: LumaNestTheme.light,
        home: TodayPage(
          snapshotAsync: AsyncData(snapshot),
          manifest: ManifestPolicy.build(snapshot, now: snapshot.observedAt),
        ),
      ),
    );

    await _scrollThrough(tester);
    _expectNoLayoutException(tester);
  });

  testWidgets('探索状态页在紧凑屏幕不溢出', (tester) async {
    _useCompactView(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider.overrideWithValue(EnvironmentConfig()),
        ],
        child: MaterialApp(
          theme: LumaNestTheme.light,
          home: const Scaffold(body: ExplorePage()),
        ),
      ),
    );

    await tester.pump();
    _expectNoLayoutException(tester);
  });

  testWidgets('路线在紧凑屏幕完整滚动且不溢出', (tester) async {
    _useCompactView(tester);
    final snapshot = ContextFixtures.drivingActiveRoute();
    final route = DrivingRoute(
      destinationName: '湖岸机位',
      distanceMeters: 16800,
      durationSeconds: 3200,
      tollsYuan: 12,
      polyline: const [
        GeoPoint(latitude: 30.6, longitude: 104.1),
        GeoPoint(latitude: 30.7, longitude: 104.2),
      ],
      instructions: const ['沿主路向西行驶', '在观景道路口转弯'],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LumaNestTheme.light,
          home: Scaffold(
            body: RoutePage(
              destinationName: route.destinationName,
              destinationLatitude: 30.7,
              destinationLongitude: 104.2,
              routeAsync: AsyncData(route),
              contextSnapshot: snapshot,
              timelineNow: snapshot.observedAt,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await _scrollThrough(tester, passes: 8);
    _expectNoLayoutException(tester);
  });

  testWidgets('灵感在紧凑屏幕完整滚动且不溢出', (tester) async {
    _useCompactView(tester);
    final snapshot = ContextFixtures.lakeSunset(observedAt: DateTime.now());
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LumaNestTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: InspirationPage(snapshotAsync: AsyncData(snapshot)),
          ),
        ),
      ),
    );
    await tester.pump();

    await _scrollThrough(tester);
    _expectNoLayoutException(tester);
  });

  testWidgets('我的在紧凑屏幕完整滚动且不溢出', (tester) async {
    _useCompactView(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LumaNestTheme.light,
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pump();

    await _scrollThrough(tester, passes: 8);
    _expectNoLayoutException(tester);
  });
}

void _useCompactView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollThrough(WidgetTester tester, {int passes = 5}) async {
  final verticalScroll = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  if (verticalScroll.evaluate().isEmpty) return;
  for (var index = 0; index < passes; index += 1) {
    await tester.drag(verticalScroll.first, const Offset(0, -420));
    await tester.pump();
  }
}

void _expectNoLayoutException(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull, reason: exception?.toString());
}
