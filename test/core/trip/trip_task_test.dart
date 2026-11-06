import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/mission/mission_providers.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const destination = GeoPoint(
    latitude: 30.25,
    longitude: 120.15,
    coordinateSystem: CoordinateSystem.wgs84,
  );

  test('one task moves from planning to en-route to field', () {
    final created = DateTime.utc(2026, 11, 3, 1);
    final task = TripTask(
      id: 'trip_1',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.planning,
      createdAt: created,
    );

    final started = task.start(at: created.add(const Duration(minutes: 5)));
    final field = started.enterField(
      at: created.add(const Duration(minutes: 45)),
    );

    expect(started.stage, TripTaskStage.enRoute);
    expect(started.startedAt, created.add(const Duration(minutes: 5)));
    expect(field.stage, TripTaskStage.field);
    expect(field.startedAt, started.startedAt);
    expect(field.fieldEnteredAt, created.add(const Duration(minutes: 45)));
  });

  test('arriving directly still creates a valid field task', () {
    final task = TripTask(
      id: 'trip_2',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.walking,
      stage: TripTaskStage.planning,
      createdAt: createdAt,
    );

    final field = task.enterField(
      at: createdAt.add(const Duration(minutes: 2)),
    );

    expect(field.stage, TripTaskStage.field);
    expect(field.startedAt, createdAt.add(const Duration(minutes: 2)));
  });

  test('terminal tasks cannot be started again', () {
    final task = TripTask(
      id: 'trip_3',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.planning,
      createdAt: createdAt,
    );

    expect(
      () => task
          .enterField(at: createdAt)
          .complete(at: createdAt)
          .start(at: createdAt),
      throwsStateError,
    );
  });

  test('field tasks cannot move backwards to en-route', () {
    final task = TripTask(
      id: 'trip_4',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.field,
      createdAt: createdAt,
    );

    expect(() => task.start(at: createdAt), throwsStateError);
  });

  test('tasks must enter the field before they can be completed', () {
    final task = TripTask(
      id: 'trip_5',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.enRoute,
      createdAt: createdAt,
    );

    expect(() => task.complete(at: createdAt), throwsStateError);
  });

  test('parses only explicit task commands', () {
    expect(TripTaskCommandParser.parse('带我去西湖')?.destinationQuery, '西湖');
    expect(
      TripTaskCommandParser.parse('开始出发')?.type,
      TripTaskCommandType.start,
    );
    expect(
      TripTaskCommandParser.parse('我到了，进入现场')?.type,
      TripTaskCommandType.enterField,
    );
    expect(
      TripTaskCommandParser.parse('停止守候')?.type,
      TripTaskCommandType.stopWatch,
    );
    expect(TripTaskCommandParser.parse('什么时候出发？'), isNull);
  });

  test('round-trips the persisted task contract', () {
    final task = TripTask(
      id: 'trip_saved',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.field,
      createdAt: createdAt,
      startedAt: createdAt.add(const Duration(minutes: 5)),
      fieldEnteredAt: createdAt.add(const Duration(minutes: 45)),
      sessionId: 'session_1',
      targetId: 'target_1',
      remoteMissionId: 'mis_0123456789abcdef0123456789abcdef',
      remoteMissionVersion: 4,
      remoteMissionStage: MissionRemoteStage.field,
      watchEnabled: true,
    );

    final restored = TripTask.fromJson(task.toJson());

    expect(restored?.id, task.id);
    expect(restored?.destination.latitude, destination.latitude);
    expect(restored?.stage, TripTaskStage.field);
    expect(restored?.fieldEnteredAt, task.fieldEnteredAt);
    expect(restored?.sessionId, 'session_1');
    expect(restored?.remoteMissionId, task.remoteMissionId);
    expect(restored?.remoteMissionVersion, 4);
    expect(restored?.remoteMissionStage, MissionRemoteStage.field);
  });

  test('legacy watch is suspended without discarding the trip', () {
    final task = TripTask(
      id: 'legacy',
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
      stage: TripTaskStage.planning,
      createdAt: createdAt,
      watchEnabled: true,
      remoteMissionId: 'mis_0123456789abcdef0123456789abcdef',
      remoteMissionVersion: 1,
    );
    final json = task.toJson()..['version'] = 2;
    final restored = TripTask.fromJson(json);
    expect(restored?.destinationName, '西湖');
    expect(restored?.watchEnabled, isFalse);
    expect(restored?.remoteMissionWatchEnabled, isNull);
  });

  test(
    'watch intent revision survives restart and increases for each change',
    () async {
      final store = _FakeTripTaskStore(null);
      final container = ProviderContainer(
        overrides: [tripTaskStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await controller.ready;
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(tripTaskProvider)?.watchIntentRevision, 1);
      controller.setWatchEnabled(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(tripTaskProvider)?.watchIntentRevision, 2);
      final restored = TripTask.fromJson(store.value!.toJson());
      expect(restored?.watchIntentRevision, 2);
    },
  );

  test(
    'SQLite migration preserves the old trip and clear cannot resurrect it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesAsync();
      final task = TripTask(
        id: 'legacy_sqlite',
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
        stage: TripTaskStage.planning,
        createdAt: createdAt,
        watchEnabled: true,
      );
      final legacy = task.toJson()..['version'] = 2;
      await preferences.setString('lumanest.trip_task.v1', jsonEncode(legacy));
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final store = DriftTripTaskStore(database, preferences);
      expect((await store.read())?.destinationName, '西湖');
      expect((await store.read())?.watchEnabled, isFalse);
      await store.clear();
      // Simulate a crash after SQLite commit but before legacy cleanup.
      await preferences.setString('lumanest.trip_task.v1', jsonEncode(legacy));
      expect(await DriftTripTaskStore(database, preferences).read(), isNull);
      expect(await preferences.getString('lumanest.trip_task.v1'), isNull);
    },
  );

  test('SQLite migration does not discard invalid legacy data', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesAsync();
    await preferences.setString('lumanest.trip_task.v1', 'invalid json');
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    await expectLater(
      DriftTripTaskStore(database, preferences).read(),
      throwsFormatException,
    );
    expect(
      await preferences.getString('lumanest.trip_task.v1'),
      'invalid json',
    );
  });

  test(
    'stop watch records a new revision when local state is already off',
    () async {
      final task = TripTask(
        id: 'trip_remote_watch',
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
        stage: TripTaskStage.planning,
        createdAt: createdAt,
        watchEnabled: false,
        remoteMissionId: 'mis_0123456789abcdef0123456789abcdef',
        remoteMissionVersion: 4,
        remoteMissionStage: MissionRemoteStage.planning,
        remoteMissionWatchEnabled: true,
        watchIntentRevision: 9,
      );
      final store = _FakeTripTaskStore(task);
      final container = ProviderContainer(
        overrides: [tripTaskStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await controller.ready;
      controller.setWatchEnabled(false);
      expect(container.read(tripTaskProvider)?.watchIntentRevision, 10);
      expect(container.read(tripTaskProvider)?.watchEnabled, isFalse);
    },
  );

  test('controller restores an open task and projects route state', () async {
    final store = _FakeTripTaskStore(
      TripTask(
        id: 'trip_saved',
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.walking,
        stage: TripTaskStage.enRoute,
        createdAt: createdAt,
      ),
    );
    final container = ProviderContainer(
      overrides: [tripTaskStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(tripTaskProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(tripTaskProvider)?.stage, TripTaskStage.enRoute);
    expect(
      container.read(routeContextStateProvider).mode,
      ContextRouteMode.hiking,
    );
    expect(
      container.read(routeContextStateProvider).stage,
      ContextRouteStage.active,
    );
  });

  test(
    'a command during restore cannot overwrite a previously saved task',
    () async {
      final stored = TripTask(
        id: 'trip_old',
        destinationName: '旧目的地',
        destination: destination,
        travelMode: TripTravelMode.driving,
        stage: TripTaskStage.planning,
        createdAt: createdAt,
      );
      final store = _BlockingReadTripTaskStore(stored);
      final container = ProviderContainer(
        overrides: [tripTaskStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final controller = container.read(tripTaskProvider.notifier);
      expect(
        () => controller.plan(
          destinationName: '新目的地',
          destination: const GeoPoint(latitude: 31.25, longitude: 121.15),
          travelMode: TripTravelMode.driving,
        ),
        throwsStateError,
      );
      store.completeRead();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(tripTaskProvider)?.destinationName, '旧目的地');
      expect(store.value?.destinationName, '旧目的地');
    },
  );

  test('task writes are serialized in lifecycle order', () async {
    final store = _SerializingTripTaskStore();
    final container = ProviderContainer(
      overrides: [tripTaskStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final controller = container.read(tripTaskProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    controller.plan(
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
    );
    await Future<void>.delayed(Duration.zero);
    controller.start(at: createdAt);
    await Future<void>.delayed(Duration.zero);

    expect(store.startedStages, [TripTaskStage.planning]);
    store.releaseCurrentWrite();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(store.startedStages, [
      TripTaskStage.planning,
      TripTaskStage.enRoute,
    ]);
    store.releaseCurrentWrite();
  });

  test('local tasks stay local until watch is explicitly enabled', () async {
    final store = _FakeTripTaskStore(null);
    final mission = _FakeMissionRepository();
    final container = ProviderContainer(
      overrides: [
        tripTaskStoreProvider.overrideWithValue(store),
        missionRemoteRepositoryProvider.overrideWithValue(mission),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(tripTaskProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    controller.plan(
      destinationName: '西湖',
      destination: destination,
      travelMode: TripTravelMode.driving,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tripTaskProvider)?.remoteMissionId, isNull);
    expect(mission.operations, isEmpty);

    controller.setWatchEnabled(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(tripTaskProvider)?.remoteMissionId,
      startsWith('mis_'),
    );
    expect(mission.operations, ['create', 'authorizeWatch']);

    controller.start(at: createdAt);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(mission.operations, ['create', 'authorizeWatch', 'start']);
    expect(container.read(tripTaskProvider)?.remoteMissionVersion, 3);

    controller.setWatchEnabled(false);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(mission.operations, [
      'create',
      'authorizeWatch',
      'start',
      'setWatch',
    ]);
    expect(container.read(tripTaskProvider)?.watchEnabled, false);
  });

  test(
    'cannot replace a cloud trip while cancellation is unconfirmed',
    () async {
      final mission = _FakeMissionRepository()..failPatch = true;
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(_FakeTripTaskStore(null)),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      controller.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(
        () => controller.plan(
          destinationName: '杭州',
          destination: const GeoPoint(latitude: 30.3, longitude: 120.2),
          travelMode: TripTravelMode.driving,
        ),
        throwsStateError,
      );
      expect(container.read(tripTaskProvider)?.destinationName, '西湖');
    },
  );

  test(
    'stopping while create is in flight preserves intent and reconciles',
    () async {
      final mission = _BlockingCreateMissionRepository();
      final store = _FakeTripTaskStore(null);
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      await mission.started.future;
      expect(store.value?.remoteCreationPending, isTrue);
      controller.setWatchEnabled(false);
      expect(
        () => controller.plan(
          destinationName: '杭州',
          destination: const GeoPoint(latitude: 30.3, longitude: 120.2),
          travelMode: TripTravelMode.driving,
        ),
        throwsStateError,
      );
      mission.release.complete();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mission.operations, ['create']);
      expect(container.read(tripTaskProvider)?.watchEnabled, isFalse);
      expect(
        container.read(tripTaskProvider)?.remoteMissionWatchEnabled,
        isFalse,
      );
      expect(container.read(tripTaskProvider)?.remoteCreationPending, isFalse);
    },
  );

  test(
    'does not create a cloud mission if the recovery marker cannot be saved',
    () async {
      final mission = _FakeMissionRepository();
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(_FailingWriteTripTaskStore()),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mission.operations, isEmpty);
      expect(container.read(tripTaskProvider)?.remoteCreationPending, isTrue);
    },
  );

  test(
    'restores and retries an unconfirmed cancellation after restart',
    () async {
      final mission = _FakeMissionRepository();
      final store = _FakeTripTaskStore(
        TripTask(
          id: 'trip_pending_cancel',
          destinationName: '西湖',
          destination: destination,
          travelMode: TripTravelMode.driving,
          stage: TripTaskStage.cancelled,
          createdAt: createdAt,
          remoteMissionId: 'mis_0123456789abcdef0123456789abcdef',
          remoteMissionVersion: 1,
          remoteMissionStage: MissionRemoteStage.planning,
          remoteMissionWatchEnabled: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      container.read(tripTaskProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(mission.operations, contains('cancel'));
      expect(
        container.read(tripTaskProvider)?.remoteMissionStage,
        MissionRemoteStage.cancelled,
      );
    },
  );

  test(
    'retries an uncertain create with the same operation ID after restart',
    () async {
      final mission = _LostCreateResponseRepository();
      final store = _FakeTripTaskStore(null);
      ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      final first = makeContainer();
      final controller = first.read(tripTaskProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.value?.remoteCreationPending, isTrue);
      expect(mission.createKeys.length, 1);
      first.dispose();
      final second = makeContainer();
      addTearDown(second.dispose);
      second.read(tripTaskProvider);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mission.createKeys.length, 2);
      expect(mission.createKeys[1], mission.createKeys[0]);
      expect(second.read(tripTaskProvider)?.remoteMissionId, isNotNull);
      expect(second.read(tripTaskProvider)?.remoteMissionWatchEnabled, isTrue);
    },
  );

  test(
    'lost enable response is replayed before applying a later stop',
    () async {
      final mission = _LostWatchResponseRepository();
      final store = _FakeTripTaskStore(null);
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.value?.pendingWatchEnabled, isTrue);
      expect(mission.currentWatch, isTrue);
      expect(store.value?.pendingWatchIntentRevision, 1);
      controller.setWatchEnabled(false);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mission.watchKeys.length, 3);
      expect(mission.watchKeys[0], mission.watchKeys[1]);
      expect(mission.watchKeys[2], isNot(mission.watchKeys[1]));
      expect(mission.watchIntentRevisions, [1, 1, 2]);
      expect(mission.currentWatch, isFalse);
      expect(container.read(tripTaskProvider)?.pendingWatchVersion, isNull);
      expect(
        container.read(tripTaskProvider)?.remoteMissionWatchEnabled,
        isFalse,
      );
    },
  );

  test(
    'lost transition response is replayed before a later cancellation',
    () async {
      final mission = _LostTransitionResponseRepository();
      final store = _FakeTripTaskStore(null);
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await controller.ready;
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.start();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.value?.pendingTransition, 'start');
      controller.cancel();
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mission.startKeys.length, 2);
      expect(mission.startKeys.first, mission.startKeys.last);
      expect(
        container.read(tripTaskProvider)?.remoteMissionStage,
        MissionRemoteStage.cancelled,
      );
      expect(container.read(tripTaskProvider)?.pendingTransition, isNull);
    },
  );

  test(
    'historical replay cannot replace a newer remote cancellation',
    () async {
      final mission = _LostTransitionResponseRepository();
      final store = _FakeTripTaskStore(null);
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await controller.ready;
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.start();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.value?.pendingTransition, 'start');
      mission.currentStage = MissionRemoteStage.cancelled;
      mission.currentWatch = false;
      mission.version += 1;
      controller.cancel();
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        container.read(tripTaskProvider)?.remoteMissionStage,
        MissionRemoteStage.cancelled,
      );
      expect(
        container.read(tripTaskProvider)?.remoteMissionVersion,
        mission.version,
      );
      expect(
        mission.operations.where((operation) => operation == 'cancel'),
        isEmpty,
      );
    },
  );

  test(
    'a rejected cancellation reconciles the current version and retries',
    () async {
      final mission = _VersionConflictMissionRepository();
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(_FakeTripTaskStore(null)),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripTaskProvider.notifier);
      await controller.ready;
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.cancel();
      for (var i = 0; i < 18; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(mission.conflicts, 1);
      expect(mission.currentStage, MissionRemoteStage.cancelled);
      expect(
        container.read(tripTaskProvider)?.remoteMissionStage,
        MissionRemoteStage.cancelled,
      );
    },
  );

  test(
    'legacy create can recover a matching cancelled Mission without creating another',
    () async {
      final mission = _LegacyCreateMissionRepository();
      final store = _FakeTripTaskStore(
        TripTask(
          id: 'legacy_trip',
          destinationName: '西湖',
          destination: destination,
          travelMode: TripTravelMode.driving,
          stage: TripTaskStage.cancelled,
          createdAt: createdAt,
          remoteCreationPending: true,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(store),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      addTearDown(container.dispose);
      container.read(tripTaskProvider);
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        container.read(tripTaskProvider)?.remoteMissionId,
        mission.remoteId,
      );
      expect(
        container.read(tripTaskProvider)?.remoteMissionStage,
        MissionRemoteStage.cancelled,
      );
      expect(container.read(tripTaskProvider)?.remoteCreationPending, isFalse);
      expect(mission.operations, isEmpty);
    },
  );

  test('legacy create does not attach a different destination', () async {
    final mission = _LegacyCreateMissionRepository()..remoteName = '杭州';
    final store = _FakeTripTaskStore(
      TripTask(
        id: 'legacy_trip',
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
        stage: TripTaskStage.planning,
        createdAt: createdAt,
        remoteCreationPending: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        tripTaskStoreProvider.overrideWithValue(store),
        missionRemoteRepositoryProvider.overrideWithValue(mission),
      ],
    );
    addTearDown(container.dispose);
    container.read(tripTaskProvider);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(tripTaskProvider)?.remoteMissionId, isNull);
    expect(container.read(tripTaskProvider)?.remoteCreationPending, isTrue);
  });

  test(
    'SQLite restart retains a lost watch operation and the later stop',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'lumanest-trip-restart-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/trip.sqlite');
      final preferences = SharedPreferencesAsync();
      await preferences.remove('lumanest.trip_task.v1');
      final mission = _LostWatchResponseRepository();
      final firstDb = AppDatabase(NativeDatabase(file));
      final first = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(
            DriftTripTaskStore(firstDb, preferences),
          ),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      final controller = first.read(tripTaskProvider.notifier);
      await controller.ready;
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      controller.setWatchEnabled(true);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(mission.currentWatch, isTrue);
      expect(first.read(tripTaskProvider)?.pendingWatchEnabled, isTrue);
      // Simulate going offline before the stop; prevent the queued retry.
      mission.offline = true;
      controller.setWatchEnabled(false);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      first.dispose();
      await firstDb.close();
      mission.offline = false;
      final secondDb = AppDatabase(NativeDatabase(file));
      final second = ProviderContainer(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(
            DriftTripTaskStore(secondDb, preferences),
          ),
          missionRemoteRepositoryProvider.overrideWithValue(mission),
        ],
      );
      second.read(tripTaskProvider);
      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(mission.currentWatch, isFalse);
      expect(second.read(tripTaskProvider)?.remoteMissionWatchEnabled, isFalse);
      second.dispose();
      await secondDb.close();
    },
  );
}

final createdAt = DateTime.utc(2026, 11, 3, 1);

class _FakeTripTaskStore implements TripTaskStore {
  _FakeTripTaskStore(this.value);

  TripTask? value;

  @override
  Future<TripTask?> read() async => value;

  @override
  Future<void> write(TripTask task) async => value = task;

  @override
  Future<void> clear() async => value = null;
}

class _BlockingReadTripTaskStore implements TripTaskStore {
  _BlockingReadTripTaskStore(this.value);

  TripTask? value;
  final _readCompleter = Completer<TripTask?>();

  void completeRead() => _readCompleter.complete(value);

  @override
  Future<TripTask?> read() => _readCompleter.future;

  @override
  Future<void> write(TripTask task) async => value = task;

  @override
  Future<void> clear() async => value = null;
}

class _FailingWriteTripTaskStore implements TripTaskStore {
  @override
  Future<TripTask?> read() async => null;
  @override
  Future<void> write(TripTask task) async => throw StateError('disk failure');
  @override
  Future<void> clear() async {}
}

class _SerializingTripTaskStore implements TripTaskStore {
  TripTask? value;
  final startedStages = <TripTaskStage>[];
  Completer<void>? _writeRelease;

  @override
  Future<TripTask?> read() async => value;

  @override
  Future<void> write(TripTask task) async {
    startedStages.add(task.stage);
    final release = Completer<void>();
    _writeRelease = release;
    await release.future;
    value = task;
  }

  void releaseCurrentWrite() {
    final release = _writeRelease;
    if (release == null || release.isCompleted) return;
    release.complete();
  }

  @override
  Future<void> clear() async => value = null;
}

class _FakeMissionRepository implements MissionRemoteRepository {
  final operations = <String>[];
  int version = 1;
  MissionRemoteStage currentStage = MissionRemoteStage.planning;
  bool currentWatch = false;
  bool failPatch = false;

  @override
  Future<MissionOperationRecord?> getOperation(String operationId) async =>
      null;

  @override
  Future<MissionRemoteSnapshot?> get(String missionId) async =>
      MissionRemoteSnapshot(
        id: missionId,
        stage: currentStage,
        version: version,
        watchEnabled: currentWatch,
      );

  @override
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  }) async {
    operations.add('create');
    currentWatch = draft.watchEnabled;
    return MissionRemoteSnapshot(
      id: 'mis_0123456789abcdef0123456789abcdef',
      stage: MissionRemoteStage.planning,
      version: version,
      watchEnabled: draft.watchEnabled,
    );
  }

  @override
  Future<MissionRemoteSnapshot?> patch(
    String missionId, {
    required int expectedVersion,
    required String operation,
    required String operationId,
    bool? watchEnabled,
    int? intentRevision,
  }) async {
    if (failPatch) return null;
    operations.add(operation);
    version += 1;
    final stage = switch (operation) {
      'start' => MissionRemoteStage.enRoute,
      'arrive' => MissionRemoteStage.field,
      'complete' => MissionRemoteStage.completed,
      'cancel' => MissionRemoteStage.cancelled,
      _ => currentStage,
    };
    currentStage = stage;
    currentWatch = watchEnabled ?? currentWatch;
    return MissionRemoteSnapshot(
      id: missionId,
      stage: stage,
      version: version,
      watchEnabled: currentWatch,
    );
  }
}

class _BlockingCreateMissionRepository extends _FakeMissionRepository {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  }) async {
    started.complete();
    await release.future;
    return super.create(draft, operationId: operationId);
  }
}

class _LostCreateResponseRepository extends _FakeMissionRepository {
  final createKeys = <String>[];
  MissionRemoteSnapshot? created;

  @override
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  }) async {
    createKeys.add(operationId);
    if (created == null) {
      created = await super.create(draft, operationId: operationId);
      return null; // The server committed, but the response was lost.
    }
    return created;
  }
}

class _LostWatchResponseRepository extends _FakeMissionRepository {
  final watchKeys = <String>[];
  final watchIntentRevisions = <int?>[];
  MissionRemoteSnapshot? firstResponse;
  bool offline = false;

  @override
  Future<MissionRemoteSnapshot?> patch(
    String missionId, {
    required int expectedVersion,
    required String operation,
    required String operationId,
    bool? watchEnabled,
    int? intentRevision,
  }) async {
    if (offline) return null;
    if (operation != 'setWatch' && operation != 'authorizeWatch') {
      return super.patch(
        missionId,
        expectedVersion: expectedVersion,
        operation: operation,
        operationId: operationId,
        watchEnabled: watchEnabled,
      );
    }
    watchKeys.add(operationId);
    watchIntentRevisions.add(intentRevision);
    if (watchKeys.length == 2) return firstResponse;
    final response = await super.patch(
      missionId,
      expectedVersion: expectedVersion,
      operation: operation,
      operationId: operationId,
      watchEnabled: watchEnabled,
    );
    if (watchKeys.length == 1) {
      firstResponse = response;
      return null;
    }
    return response;
  }
}

class _LostTransitionResponseRepository extends _FakeMissionRepository {
  final startKeys = <String>[];
  MissionRemoteSnapshot? started;

  @override
  Future<MissionRemoteSnapshot?> patch(
    String missionId, {
    required int expectedVersion,
    required String operation,
    required String operationId,
    bool? watchEnabled,
    int? intentRevision,
  }) async {
    if (operation != 'start') {
      return super.patch(
        missionId,
        expectedVersion: expectedVersion,
        operation: operation,
        operationId: operationId,
        watchEnabled: watchEnabled,
      );
    }
    startKeys.add(operationId);
    if (started != null) return started;
    started = await super.patch(
      missionId,
      expectedVersion: expectedVersion,
      operation: operation,
      operationId: operationId,
      watchEnabled: watchEnabled,
    );
    return null;
  }
}

class _VersionConflictMissionRepository extends _FakeMissionRepository {
  int conflicts = 0;
  @override
  Future<MissionRemoteSnapshot?> patch(
    String missionId, {
    required int expectedVersion,
    required String operation,
    required String operationId,
    bool? watchEnabled,
    int? intentRevision,
  }) async {
    if (operation == 'cancel' && conflicts == 0) {
      conflicts++;
      version++;
      throw MissionVersionConflict((await get(missionId))!);
    }
    return super.patch(
      missionId,
      expectedVersion: expectedVersion,
      operation: operation,
      operationId: operationId,
      watchEnabled: watchEnabled,
    );
  }
}

class _LegacyCreateMissionRepository extends _FakeMissionRepository {
  final remoteId = 'mis_0123456789abcdef0123456789abcdef';
  String remoteName = '西湖';

  @override
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  }) async => throw const MissionLegacyOperationUnverifiable();

  @override
  Future<MissionOperationRecord?> getOperation(String operationId) async =>
      MissionOperationRecord(
        missionId: remoteId,
        verifiable: false,
        status: 201,
      );

  @override
  Future<MissionRemoteSnapshot?> get(String missionId) async =>
      MissionRemoteSnapshot(
        id: remoteId,
        stage: MissionRemoteStage.cancelled,
        version: 3,
        watchEnabled: false,
        destinationName: remoteName,
        destinationLatitude: 30.25,
        destinationLongitude: 120.15,
        destinationSystem: 'wgs84',
        intent: 'photography',
      );
}
