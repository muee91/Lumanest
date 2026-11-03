import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/mission/mission_providers.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';

void main() {
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
    'a command accepted during restore is newer than the stored snapshot',
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
      final current = controller.plan(
        destinationName: '新目的地',
        destination: const GeoPoint(
          latitude: 31.25,
          longitude: 121.15,
          coordinateSystem: CoordinateSystem.wgs84,
        ),
        travelMode: TripTravelMode.driving,
      );
      store.completeRead();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(tripTaskProvider), same(current));
      expect(store.value?.destinationName, '新目的地');
    },
  );

  test('task writes are serialized in lifecycle order', () async {
    final store = _SerializingTripTaskStore();
    final container = ProviderContainer(
      overrides: [tripTaskStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final controller = container.read(tripTaskProvider.notifier);
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

  test(
    'new tasks are mirrored to the server and lifecycle updates are versioned',
    () async {
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
      controller.plan(
        destinationName: '西湖',
        destination: destination,
        travelMode: TripTravelMode.driving,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(tripTaskProvider)?.remoteMissionId,
        startsWith('mis_'),
      );
      expect(mission.operations, ['create']);

      controller.start(at: createdAt);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(mission.operations, ['create', 'start']);
      expect(container.read(tripTaskProvider)?.remoteMissionVersion, 2);

      controller.setWatchEnabled(false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(mission.operations, ['create', 'start', 'setWatch']);
      expect(container.read(tripTaskProvider)?.watchEnabled, false);
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

  @override
  Future<MissionRemoteSnapshot?> create(
    MissionDraft draft, {
    required String operationId,
  }) async {
    operations.add('create');
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
  }) async {
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
    return MissionRemoteSnapshot(
      id: missionId,
      stage: stage,
      version: version,
      watchEnabled: watchEnabled ?? true,
    );
  }
}
