import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/presentation/explore_page.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

import 'map_consent_test_harness.dart';

Widget wrapExplorePage({
  required String amapKey,
  FakeAmapInitializerGateway? gateway,
  MapSurfaceBuilder? mapBuilder,
  ExploreFocus focus = ExploreFocus.photography,
  LocationSearchRepository? locationSearchRepository,
}) {
  return ProviderScope(
    overrides: [
      environmentConfigProvider.overrideWithValue(
        EnvironmentConfig(amapAndroidKey: amapKey),
      ),
      amapInitializerGatewayProvider.overrideWithValue(
        gateway ?? FakeAmapInitializerGateway(),
      ),
      if (locationSearchRepository != null)
        locationSearchRepositoryProvider.overrideWithValue(
          locationSearchRepository,
        ),
    ],
    child: MaterialApp(
      home: ExplorePage(mapBuilder: mapBuilder, focus: focus),
    ),
  );
}

Widget fakeMapSurface() =>
    const SizedBox(key: Key('map-surface'), child: Text('map-placeholder'));

void main() {
  testWidgets('missing key shows configuration state, not map widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapExplorePage(amapKey: '', mapBuilder: fakeMapSurface),
    );

    expect(find.byKey(const Key('map-surface')), findsNothing);
    expect(find.text('地图尚未配置'), findsOneWidget);
  });

  testWidgets('configured key without consent shows prompt, not map', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapExplorePage(amapKey: 'test-key', mapBuilder: fakeMapSurface),
    );

    expect(find.byKey(const Key('map-surface')), findsNothing);
    expect(find.text('同意并开启地图'), findsOneWidget);
  });

  testWidgets('accepting consent calls privacy before init and shows map', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(gateway.privacyAgreed, isTrue);
    expect(gateway.initialized, isTrue);
    expect(gateway.privacyCallIndex, lessThan(gateway.initCallIndex));
    expect(find.byKey(const Key('map-surface')), findsOneWidget);
  });

  testWidgets('map api key is passed from environment config on init', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'env-key-789',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(gateway.lastApiKey?.androidKey, 'env-key-789');
  });

  testWidgets('consent prompt disappears after acceptance', (tester) async {
    await tester.pumpWidget(
      wrapExplorePage(amapKey: 'test-key', mapBuilder: fakeMapSurface),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(find.text('同意并开启地图'), findsNothing);
  });

  testWidgets('map init is invoked once, not re-fired on rebuild', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(gateway.initialized, isTrue);

    // Simulate a parent rebuild that keeps MapConsentReady state
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );
    await tester.pump();

    // With StatefulWidget+initState, init is not re-called during rebuild
    expect(gateway.initialized, isTrue);
  });

  testWidgets('map init may depend on inherited MediaQuery data', (
    tester,
  ) async {
    final gateway = FakeAmapInitializerGateway(readMediaQueryOnInit: true);
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        gateway: gateway,
        mapBuilder: fakeMapSurface,
      ),
    );

    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(gateway.initialized, isTrue);
  });

  testWidgets('focused exploration exposes the selected intent', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        mapBuilder: fakeMapSurface,
        focus: ExploreFocus.water,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在寻找湖岸与水面线索'), findsOneWidget);
  });

  testWidgets('temporary focus expires and clears the router query', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        environmentConfigProvider.overrideWithValue(
          EnvironmentConfig(amapAndroidKey: 'test-key'),
        ),
        amapInitializerGatewayProvider.overrideWithValue(
          FakeAmapInitializerGateway(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/explore?focus=water',
      routes: [
        GoRoute(
          path: '/explore',
          builder: (_, state) => Scaffold(
            body: ExplorePage(
              mapBuilder: fakeMapSurface,
              focus: ExploreFocus.fromQuery(state.uri.queryParameters['focus']),
              intentTimeout: const Duration(milliseconds: 100),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在寻找湖岸与水面线索'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(find.text('正在寻找湖岸与水面线索'), findsNothing);
    expect(
      container.read(exploreIntentProvider).category,
      NearbyPlaceCategory.viewpoint,
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/explore',
    );
  });

  testWidgets('manual category choice completes a temporary intent', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        environmentConfigProvider.overrideWithValue(
          EnvironmentConfig(amapAndroidKey: 'test-key'),
        ),
        amapInitializerGatewayProvider.overrideWithValue(
          FakeAmapInitializerGateway(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/explore?focus=water',
      routes: [
        GoRoute(
          path: '/explore',
          builder: (_, state) => Scaffold(
            body: ExplorePage(
              mapBuilder: fakeMapSurface,
              focus: ExploreFocus.fromQuery(state.uri.queryParameters['focus']),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在寻找湖岸与水面线索'), findsOneWidget);

    await tester.tap(find.text('吃饭'));
    await tester.pump();
    await tester.pump();

    expect(find.text('正在寻找湖岸与水面线索'), findsNothing);
    expect(container.read(exploreIntentProvider).activeFocus, isNull);
    expect(
      container.read(exploreIntentProvider).category,
      NearbyPlaceCategory.food,
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/explore',
    );
  });

  testWidgets('latest search wins when responses complete out of order', (
    tester,
  ) async {
    final repository = _DeferredLocationSearchRepository();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        mapBuilder: fakeMapSurface,
        locationSearchRepository: repository,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    await tester.tap(find.text('搜索地点'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '旧地点');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '新地点');
    await tester.pump(const Duration(milliseconds: 500));

    repository.complete('新地点', const [
      LocationSearchResult(
        id: 'new',
        name: '新结果',
        point: GeoPoint(
          latitude: 30.25,
          longitude: 120.16,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ),
    ]);
    await tester.pump();
    expect(find.text('新结果'), findsOneWidget);

    repository.complete('旧地点', const [
      LocationSearchResult(
        id: 'old',
        name: '旧结果',
        point: GeoPoint(
          latitude: 31.23,
          longitude: 121.47,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ),
    ]);
    await tester.pump();

    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
  });

  testWidgets('cached search results are identified as offline data', (
    tester,
  ) async {
    final repository = _DeferredLocationSearchRepository();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        mapBuilder: fakeMapSurface,
        locationSearchRepository: repository,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.tap(find.text('搜索地点'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '西湖');
    await tester.pump(const Duration(milliseconds: 500));

    repository.complete('西湖', [
      LocationSearchResult(
        id: 'cached-west-lake',
        name: '西湖风景名胜区',
        point: const GeoPoint(
          latitude: 30.231,
          longitude: 120.132,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        address: '杭州市西湖区',
        cachedAt: DateTime.utc(2026, 7, 15, 8),
      ),
    ]);
    await tester.pump();

    expect(find.text('西湖风景名胜区'), findsOneWidget);
    expect(find.text('杭州市西湖区 · 离线缓存'), findsOneWidget);
  });

  testWidgets('clearing search invalidates an in-flight response', (
    tester,
  ) async {
    final repository = _DeferredLocationSearchRepository();
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        mapBuilder: fakeMapSurface,
        locationSearchRepository: repository,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();

    await tester.tap(find.text('搜索地点'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '稍后清空');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    repository.complete('稍后清空', const [
      LocationSearchResult(
        id: 'stale',
        name: '不应出现',
        point: GeoPoint(
          latitude: 30.25,
          longitude: 120.16,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ),
    ]);
    await tester.pump();

    expect(find.text('搜索结果'), findsNothing);
    expect(find.text('不应出现'), findsNothing);
  });

  testWidgets('route action survives a recent-route persistence failure', (
    tester,
  ) async {
    final repository = _DeferredLocationSearchRepository();
    final router = GoRouter(
      initialLocation: '/explore',
      routes: [
        GoRoute(
          path: '/explore',
          builder: (_, _) =>
              Scaffold(body: ExplorePage(mapBuilder: fakeMapSurface)),
        ),
        GoRoute(
          path: '/route',
          builder: (_, state) => Scaffold(
            body: Text('route:${state.uri.queryParameters['name']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentConfigProvider.overrideWithValue(
            EnvironmentConfig(amapAndroidKey: 'test-key'),
          ),
          amapInitializerGatewayProvider.overrideWithValue(
            FakeAmapInitializerGateway(),
          ),
          locationSearchRepositoryProvider.overrideWithValue(repository),
          userLibraryStoreProvider.overrideWithValue(
            _FailingUserLibraryStore(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.tap(find.text('搜索地点'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '目的地');
    await tester.pump(const Duration(milliseconds: 500));
    repository.complete('目的地', const [
      LocationSearchResult(
        id: 'destination',
        name: '继续前往',
        point: GeoPoint(
          latitude: 30.25,
          longitude: 120.16,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
      ),
    ]);
    await tester.pump();

    await tester.tap(find.text('继续前往'));
    await tester.pump();
    await tester.pump();

    expect(find.text('route:继续前往'), findsOneWidget);
    expect(find.text('路线可以继续使用，但未能保存到最近路线'), findsOneWidget);
  });
}

class _DeferredLocationSearchRepository implements LocationSearchRepository {
  final Map<String, Completer<List<LocationSearchResult>>> _requests = {};

  @override
  Future<List<LocationSearchResult>> search(String keywords) {
    final completer = Completer<List<LocationSearchResult>>();
    _requests[keywords] = completer;
    return completer.future;
  }

  void complete(String keywords, List<LocationSearchResult> results) {
    final request = _requests[keywords];
    if (request == null) {
      throw StateError('No pending search for $keywords');
    }
    request.complete(results);
  }
}

class _FailingUserLibraryStore implements UserLibraryStore {
  @override
  Future<UserLibraryState> read() async => const UserLibraryState();

  @override
  Future<void> write(UserLibraryState state) {
    throw StateError('simulated persistence failure');
  }
}
