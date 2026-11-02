import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
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
      () => task.complete(at: createdAt).start(at: createdAt),
      throwsStateError,
    );
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
    );

    final restored = TripTask.fromJson(task.toJson());

    expect(restored?.id, task.id);
    expect(restored?.destination.latitude, destination.latitude);
    expect(restored?.stage, TripTaskStage.field);
    expect(restored?.fieldEnteredAt, task.fieldEnteredAt);
    expect(restored?.sessionId, 'session_1');
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
