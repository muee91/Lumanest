import 'package:flutter_test/flutter_test.dart';
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
}

final createdAt = DateTime.utc(2026, 11, 3, 1);
