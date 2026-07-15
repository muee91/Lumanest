import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_event.dart' as context;
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/notifications/application/route_reminder_service.dart';
import 'package:luma_nest/src/features/route/application/gpx_track_import_service.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:luma_nest/src/features/route/presentation/route_page.dart';

DrivingRoute _drivingRoute() => DrivingRoute(
  destinationName: '湖岸机位',
  distanceMeters: 5000,
  durationSeconds: const Duration(hours: 2).inSeconds,
  tollsYuan: 0,
  polyline: const [],
);

Widget _routeApp(
  ProviderContainer container, {
  AsyncValue<DrivingRoute>? routeAsync,
  RouteTravelMode travelMode = RouteTravelMode.driving,
  String destinationName = '湖岸机位',
  double destinationLatitude = 31,
  double destinationLongitude = 121,
  ContextSnapshot? contextSnapshot,
  DateTime? timelineNow,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation:
            '/route?name=$destinationName&lat=$destinationLatitude&lon=$destinationLongitude&mode=${travelMode.name}',
        routes: [
          GoRoute(
            path: '/route',
            builder: (context, state) => Scaffold(
              body: RoutePage(
                destinationName: state.uri.queryParameters['name'],
                destinationLatitude: double.tryParse(
                  state.uri.queryParameters['lat'] ?? '',
                ),
                destinationLongitude: double.tryParse(
                  state.uri.queryParameters['lon'] ?? '',
                ),
                routeAsync: routeAsync,
                travelMode: travelMode,
                contextSnapshot: contextSnapshot,
                timelineNow: timelineNow,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
      events: [
        context.ContextEvent(
          id: 'strong-wind',
          channel: context.ContextEventChannel.safety,
          source: context.ContextEventSource.weather,
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 15)),
          confidence: 0.9,
          geoScope: context.ContextGeoScope.route,
          safetyLevel: context.ContextSafetyLevel.warning,
          allowedAction: context.ContextAction.openSafety,
        ),
      ],
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
    expect(find.text('路线风险节点'), findsOneWidget);
    expect(find.text('行动时间轴'), findsOneWidget);
    expect(find.text('落日窗口'), findsOneWidget);
    expect(find.text('蓝调窗口'), findsOneWidget);
    expect(find.textContaining('未推断沿途未来天气'), findsOneWidget);
  });

  testWidgets('automatically merges corridor support into the timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 7, 15, 8);
    final route = DrivingRoute(
      destinationName: '湖岸营地',
      distanceMeters: 8000,
      durationSeconds: const Duration(hours: 1).inSeconds,
      tollsYuan: 0,
      polyline: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.1, longitude: 120.1),
      ],
    );
    final snapshot = ContextSnapshot(
      id: 'support-context',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.driving,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nearbyPlaceRepositoryProvider.overrideWithValue(
            _TimelineNearbyPlaceRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RoutePage(
              destinationName: '湖岸营地',
              destinationLatitude: 30.1,
              destinationLongitude: 120.1,
              routeAsync: AsyncData(route),
              contextSnapshot: snapshot,
              timelineNow: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('行动时间轴'), findsOneWidget);
    expect(find.text('沿途小店'), findsWidgets);
    expect(find.textContaining('时间为进度估算'), findsOneWidget);
    expect(find.text('重新扫描沿途服务点'), findsOneWidget);
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
    expect(find.text('扫描沿途餐饮和补给'), findsOneWidget);
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

  testWidgets('empty route page exposes real track import', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Scaffold(body: RoutePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('创建路线'), findsOneWidget);
    expect(find.text('导入轨迹'), findsOneWidget);
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
  });

  testWidgets('imports, saves and opens a GPX track without route network', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 7, 15, 4);
    final track = ImportedRouteTrack(
      id: 'track-imported',
      name: '山谷徒步线',
      importedAt: now,
      points: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.01, longitude: 120.01),
      ],
      distanceMeters: 1500,
      durationSeconds: 1200,
      durationEstimated: false,
      ascentMeters: 90,
      descentMeters: 30,
    );
    final store = _MemoryLibraryStore();
    final container = ProviderContainer(
      overrides: [
        userLibraryStoreProvider.overrideWithValue(store),
        gpxTrackImportServiceProvider.overrideWithValue(
          _FakeGpxTrackImportService(track),
        ),
      ],
    );
    addTearDown(container.dispose);
    final snapshot = ContextSnapshot(
      id: 'import-context',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.hiking,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
      sunset: now.add(const Duration(hours: 8)),
    );
    final router = GoRouter(
      initialLocation: '/route',
      routes: [
        GoRoute(
          path: '/route',
          builder: (context, state) => Scaffold(
            body: RoutePage(
              importedTrackId: state.uri.queryParameters['track'],
              contextSnapshot: snapshot,
              timelineNow: now,
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入轨迹'));
    await tester.pumpAndSettle();

    expect(store.value.importedTracks.single.id, 'track-imported');
    expect(find.text('山谷徒步线'), findsOneWidget);
    expect(find.text('本地导入轨迹'), findsOneWidget);
    expect(find.text('记录用时'), findsOneWidget);
    expect(find.text('90 m'), findsOneWidget);
    expect(find.textContaining('不包含实时路况'), findsOneWidget);
  });

  // Lifecycle coverage: the following tests verify the route context state
  // transitions that RoutePage drives through routeContextStateProvider. They
  // do not exercise turn-by-turn navigation (which is explicitly out of scope
  // for RoutePage). The "end" transition is verified by calling the notifier
  // directly because the end button also navigates via go_router, which would
  // require a full router shell; the notifier call is the exact same code path
  // the button uses.

  group('route context lifecycle', () {
    late ProviderContainer container;
    late _MemoryLibraryStore libraryStore;
    late _MemoryRouteReminderPreferenceStore reminderPreferenceStore;
    late _FakeRouteReminderService reminderService;

    setUp(() {
      libraryStore = _MemoryLibraryStore();
      reminderPreferenceStore = _MemoryRouteReminderPreferenceStore();
      reminderService = _FakeRouteReminderService();
      container = ProviderContainer(
        overrides: [
          userLibraryStoreProvider.overrideWithValue(libraryStore),
          routeReminderPreferenceStoreProvider.overrideWithValue(
            reminderPreferenceStore,
          ),
          routeReminderServiceProvider.overrideWithValue(reminderService),
        ],
      );
      addTearDown(container.dispose);
    });

    RouteContextState state() => container.read(routeContextStateProvider);

    Future<void> pumpRoute(
      WidgetTester tester, {
      RouteTravelMode travelMode = RouteTravelMode.driving,
    }) async {
      await tester.pumpWidget(
        _routeApp(
          container,
          routeAsync: AsyncData(_drivingRoute()),
          travelMode: travelMode,
        ),
      );
      // Run the post-frame callback that _RouteContent schedules in initState.
      await tester.pump();
    }

    testWidgets('marks the route as planned after a successful route loads', (
      tester,
    ) async {
      await pumpRoute(tester);
      expect(state().mode, ContextRouteMode.driving);
      expect(state().stage, ContextRouteStage.planned);
      expect(find.text('开始行程'), findsOneWidget);
    });

    testWidgets('start, pause, resume transitions drive the state', (
      tester,
    ) async {
      await pumpRoute(tester);

      await tester.tap(find.text('开始行程'));
      await tester.pump();
      expect(state(), RouteContextState.active(ContextRouteMode.driving));

      await tester.tap(find.text('暂停'));
      await tester.pump();
      expect(state(), RouteContextState.paused(ContextRouteMode.driving));

      await tester.tap(find.text('继续'));
      await tester.pump();
      expect(state(), RouteContextState.active(ContextRouteMode.driving));
    });

    testWidgets('route saving is explicit and locally reversible', (
      tester,
    ) async {
      await pumpRoute(tester);
      await container.read(userLibraryProvider.future);

      expect(find.text('保存路线'), findsOneWidget);
      await tester.tap(find.text('保存路线'));
      await tester.pumpAndSettle();

      expect(
        container.read(userLibraryProvider).requireValue.savedRoutes,
        hasLength(1),
      );
      expect(find.text('取消保存路线'), findsOneWidget);

      await tester.tap(find.text('取消保存路线'));
      await tester.pumpAndSettle();
      expect(
        container.read(userLibraryProvider).requireValue.savedRoutes,
        isEmpty,
      );
    });

    testWidgets('start and end persist a completed local journey', (
      tester,
    ) async {
      await pumpRoute(tester);

      await tester.tap(find.text('开始行程'));
      await tester.pumpAndSettle();
      expect(state().stage, ContextRouteStage.active);
      expect(libraryStore.value.activeJourney, isNotNull);

      await tester.tap(find.text('结束行程'));
      await tester.pumpAndSettle();
      expect(state(), RouteContextState.none);
      expect(libraryStore.value.activeJourney, isNull);
      expect(libraryStore.value.journeys.single.endedAt, isNotNull);
    });

    testWidgets('reopening an unfinished journey restores active following', (
      tester,
    ) async {
      libraryStore.value = UserLibraryState(
        journeys: [
          SavedJourney.start(
            const SavedRouteDestination(
              name: '湖岸机位',
              latitude: 31,
              longitude: 121,
            ),
            startedAt: DateTime.utc(2026, 7, 15, 8),
          ),
        ],
      );

      await pumpRoute(tester);
      await tester.pumpAndSettle();

      expect(state(), RouteContextState.active(ContextRouteMode.driving));
      expect(find.text('暂停'), findsOneWidget);
    });

    testWidgets('walking start schedules and end cancels a return reminder', (
      tester,
    ) async {
      reminderPreferenceStore.enabled = true;
      final now = DateTime.utc(2026, 7, 15, 8);
      final sunset = DateTime.utc(2026, 7, 15, 18);
      final snapshot = ContextSnapshot(
        id: 'walking-reminder',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        sunset: sunset,
      );
      final walkingRoute = DrivingRoute(
        destinationName: '山谷步道',
        distanceMeters: 5000,
        durationSeconds: const Duration(hours: 2).inSeconds,
        tollsYuan: 0,
        polyline: const [],
        travelMode: RouteTravelMode.walking,
      );
      await tester.pumpWidget(
        _routeApp(
          container,
          routeAsync: AsyncData(walkingRoute),
          travelMode: RouteTravelMode.walking,
          destinationName: '山谷步道',
          contextSnapshot: snapshot,
          timelineNow: now,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('开始行程'));
      await tester.pumpAndSettle();

      expect(reminderService.scheduled, hasLength(1));
      expect(
        reminderService.scheduled.single.scheduledAt,
        sunset.subtract(const Duration(hours: 2)),
      );

      await tester.tap(find.text('结束行程'));
      await tester.pumpAndSettle();
      expect(reminderService.cancelled, hasLength(1));
    });

    testWidgets('rebuild does not downgrade an active route to planned', (
      tester,
    ) async {
      await pumpRoute(tester);
      await tester.tap(find.text('开始行程'));
      await tester.pump();
      expect(state().stage, ContextRouteStage.active);

      // Rebuild with the same route data. _syncPlanned must not downgrade.
      await tester.pumpWidget(
        _routeApp(container, routeAsync: AsyncData(_drivingRoute())),
      );
      await tester.pump();

      expect(state().stage, ContextRouteStage.active);
    });

    testWidgets('a different destination on the same mode resets to planned', (
      tester,
    ) async {
      await pumpRoute(tester);
      await tester.tap(find.text('开始行程'));
      await tester.pump();
      expect(state(), RouteContextState.active(ContextRouteMode.driving));

      await tester.pumpWidget(
        _routeApp(
          container,
          routeAsync: AsyncData(_drivingRoute()),
          destinationName: '山谷机位',
          destinationLatitude: 30,
          destinationLongitude: 120,
        ),
      );
      await tester.pump();

      expect(state(), RouteContextState.planned(ContextRouteMode.driving));
      expect(find.text('开始行程'), findsOneWidget);
    });

    testWidgets('a planned route can be cancelled from the lifecycle bar', (
      tester,
    ) async {
      await pumpRoute(tester);
      expect(state(), RouteContextState.planned(ContextRouteMode.driving));

      await tester.tap(find.text('取消规划'));
      await tester.pumpAndSettle();

      expect(state(), RouteContextState.none);
      expect(find.text('取消规划'), findsNothing);
      expect(find.text('创建路线'), findsOneWidget);
    });

    testWidgets(
      'ending the route clears the state to none and shows an empty route',
      (tester) async {
        await pumpRoute(tester);
        await tester.tap(find.text('开始行程'));
        await tester.pump();
        expect(state().stage, ContextRouteStage.active);

        // The end button also calls context.go('/route'); we invoke the same
        // notifier method directly to verify the state transition without
        // requiring a full navigation assertion.
        container.read(routeContextStateProvider.notifier).end();
        await tester.pump();

        expect(state(), RouteContextState.none);
        // After end, the lifecycle bar must not offer start (no planned state).
        expect(find.text('开始行程'), findsNothing);
      },
    );

    testWidgets('walking route plans as hiking mode', (tester) async {
      await pumpRoute(tester, travelMode: RouteTravelMode.walking);
      expect(state().mode, ContextRouteMode.hiking);
      expect(state().stage, ContextRouteStage.planned);
    });
  });
}

class _FakeGpxTrackImportService implements GpxTrackImportService {
  const _FakeGpxTrackImportService(this.track);

  final ImportedRouteTrack track;

  @override
  Future<ImportedRouteTrack?> pickAndParse() async => track;
}

class _MemoryLibraryStore implements UserLibraryStore {
  UserLibraryState value = const UserLibraryState();

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}

class _MemoryRouteReminderPreferenceStore
    implements RouteReminderPreferenceStore {
  bool enabled = false;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;
}

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.journeyId,
    required this.scheduledAt,
  });

  final String journeyId;
  final DateTime scheduledAt;
}

class _FakeRouteReminderService implements RouteReminderService {
  final scheduled = <_ScheduledReminder>[];
  final cancelled = <String>[];

  @override
  Future<void> cancel(String journeyId) async => cancelled.add(journeyId);

  @override
  Future<void> cancelAll() async => cancelled.add('all');

  @override
  Future<bool> permissionGranted() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> scheduleReturnReminder({
    required String journeyId,
    required String destinationName,
    required DateTime scheduledAt,
  }) async {
    scheduled.add(
      _ScheduledReminder(journeyId: journeyId, scheduledAt: scheduledAt),
    );
    return true;
  }
}

class _TimelineNearbyPlaceRepository implements NearbyPlaceRepository {
  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    if (category != NearbyPlaceCategory.food) return const [];
    return [
      NearbyPlace(
        id: 'timeline-food',
        name: '沿途小店',
        category: category,
        point: center,
        distanceMeters: 120,
        address: '湖岸路',
      ),
    ];
  }
}
