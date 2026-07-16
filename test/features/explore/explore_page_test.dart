import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/presentation/explore_page.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/application/environment_location_display.dart';

import 'map_consent_test_harness.dart';

Widget wrapExplorePage({
  required String amapKey,
  FakeAmapInitializerGateway? gateway,
  MapSurfaceBuilder? mapBuilder,
  ExploreFocus focus = ExploreFocus.photography,
  LocationSearchRepository? locationSearchRepository,
  AsyncValue<ContextSnapshot>? snapshotAsync,
  VoidCallback? onRetry,
  VoidCallback? onOpenAppSettings,
  VoidCallback? onSelectManualLocation,
  EnvironmentLocationDisplay? locationDisplay,
  List<NearbyPlace>? nearbyPlaces,
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
      if (locationDisplay != null)
        environmentLocationDisplayProvider.overrideWithValue(locationDisplay),
      if (nearbyPlaces != null)
        nearbyPlacesProvider.overrideWith((_) async => nearbyPlaces),
    ],
    child: MaterialApp(
      home: ExplorePage(
        mapBuilder: mapBuilder,
        focus: focus,
        snapshotAsync: snapshotAsync,
        onRetry: onRetry,
        onOpenAppSettings: onOpenAppSettings,
        onSelectManualLocation: onSelectManualLocation,
      ),
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

  testWidgets('wildlife summary shows sampling caveat and dataset attribution', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 7, 16, 8);
    final snapshot = ContextSnapshot(
      id: 'wildlife-attribution',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
      location: const GeoPoint(latitude: 31.23, longitude: 121.47),
      wildlifeActivity: RegionalWildlifeActivity(
        contractVersion: 2,
        radiusKilometers: 20,
        occurrenceSampleSize: 3,
        historicalRecordConcentration: WildlifeHistoricalRecordConcentration(
          recordsWithMonth: 3,
          recordsWithTime: 2,
          months: const [WildlifeMonthConcentration(month: 5, records: 3)],
          timePeriods: const [
            WildlifePeriodConcentration(
              period: WildlifeObservationPeriod.dawn,
              records: 2,
            ),
          ],
        ),
        datasets: [
          WildlifeDatasetReference(
            datasetKey: '11111111-1111-4111-8111-111111111111',
            title: '区域观察记录',
            publisher: '开放自然实验室',
            licenses: const ['CC-BY-4.0'],
            records: 3,
            citation: '开放自然实验室（2026）。区域观察记录。',
            url: Uri.parse(
              'https://www.gbif.org/dataset/11111111-1111-4111-8111-111111111111',
            ),
          ),
        ],
        taxa: const [
          WildlifeTaxon(
            scientificName: 'Passer montanus',
            group: WildlifeGroup.bird,
            records: 3,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        snapshotAsync: AsyncData(snapshot),
        nearbyPlaces: const [],
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.tap(find.text('同意并获取位置'));
    await tester.pump();

    expect(find.textContaining('仅反映公开记录采样'), findsOneWidget);
    expect(find.textContaining('开放自然实验室《区域观察记录》'), findsOneWidget);
    expect(find.textContaining('活动规律'), findsOneWidget);
  });

  testWidgets('manual location is visibly marked as non-live', (tester) async {
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        mapBuilder: fakeMapSurface,
        locationDisplay: const EnvironmentLocationDisplay(
          label: '海宁市',
          source: EnvironmentLocationSource.manual,
        ),
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.pump();

    expect(find.text('海宁市'), findsOneWidget);
  });

  testWidgets('location failure offers retry and manual location recovery', (
    tester,
  ) async {
    var retries = 0;
    var manualSelections = 0;
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        snapshotAsync: AsyncError(StateError('offline'), StackTrace.empty),
        onRetry: () => retries++,
        onSelectManualLocation: () => manualSelections++,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.tap(find.text('同意并获取位置'));
    await tester.pump();

    expect(find.text('暂时无法获取当前位置'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('手动选择地点'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.tap(find.text('手动选择地点'));
    expect(retries, 1);
    expect(manualSelections, 1);
  });

  testWidgets('permanent location denial offers app settings', (tester) async {
    var settingsOpened = 0;
    var manualSelections = 0;
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        snapshotAsync: AsyncError(
          const EnvironmentLoadFailure(
            EnvironmentFailureKind.location,
            cause: LocationRepositoryFailure(
              LocationFailureKind.permissionDeniedForever,
            ),
          ),
          StackTrace.empty,
        ),
        onOpenAppSettings: () => settingsOpened++,
        onSelectManualLocation: () => manualSelections++,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.tap(find.text('同意并获取位置'));
    await tester.pump();

    await tester.tap(find.text('打开设置'));
    await tester.tap(find.text('手动选择地点'));
    expect(settingsOpened, 1);
    expect(manualSelections, 1);
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

  testWidgets('search uses current snapshot location and explains local rank', (
    tester,
  ) async {
    final repository = _DeferredLocationSearchRepository();
    final now = DateTime.utc(2026, 7, 16, 8);
    const currentLocation = GeoPoint(latitude: 30.25, longitude: 120.16);
    final snapshot = ContextSnapshot(
      id: 'local-search',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
      location: currentLocation,
    );
    await tester.pumpWidget(
      wrapExplorePage(
        amapKey: 'test-key',
        snapshotAsync: AsyncData(snapshot),
        nearbyPlaces: const [],
        locationSearchRepository: repository,
      ),
    );
    await tester.tap(find.text('同意并开启地图'));
    await tester.pump();
    await tester.tap(find.text('同意并获取位置'));
    await tester.pump();

    await tester.tap(find.text('搜索地点'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '湖边');
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.centerFor('湖边'), currentLocation);
    repository.complete('湖边', const [
      LocationSearchResult(
        id: 'local-lake',
        name: '附近湖岸',
        point: GeoPoint(
          latitude: 30.251,
          longitude: 120.161,
          coordinateSystem: CoordinateSystem.gcj02,
        ),
        address: '本地湖岸',
        distanceMeters: 820,
      ),
    ]);
    await tester.pump();

    expect(find.text('搜索结果 · 附近优先'), findsOneWidget);
    expect(find.text('820 m · 本地湖岸'), findsOneWidget);
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
  final Map<String, GeoPoint?> _centers = {};

  @override
  Future<List<LocationSearchResult>> search(
    String keywords, {
    GeoPoint? center,
  }) {
    final completer = Completer<List<LocationSearchResult>>();
    _requests[keywords] = completer;
    _centers[keywords] = center;
    return completer.future;
  }

  GeoPoint? centerFor(String keywords) => _centers[keywords];

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
