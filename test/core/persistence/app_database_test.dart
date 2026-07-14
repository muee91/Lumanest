import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('saved places round-trip and replace the same stable id', () async {
    await database
        .into(database.savedPlaces)
        .insert(
          SavedPlacesCompanion.insert(
            id: 'lake-viewpoint',
            name: '湖岸机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        );
    await database
        .into(database.savedPlaces)
        .insertOnConflictUpdate(
          SavedPlacesCompanion.insert(
            id: 'lake-viewpoint',
            name: '更新后的湖岸机位',
            category: 'viewpoint',
            latitude: 31,
            longitude: 121,
          ),
        );

    final rows = await database.select(database.savedPlaces).get();

    expect(rows, hasLength(1));
    expect(rows.single.name, '更新后的湖岸机位');
    expect(rows.single.latitude, 31);
    expect(rows.single.longitude, 121);
  });

  test('recent route destination is a replaceable singleton', () async {
    await database
        .into(database.recentRouteDestinations)
        .insert(
          RecentRouteDestinationsCompanion.insert(
            id: const Value(1),
            name: '山脚',
            latitude: 30,
            longitude: 120,
            travelMode: 'driving',
          ),
        );
    await database
        .into(database.recentRouteDestinations)
        .insertOnConflictUpdate(
          RecentRouteDestinationsCompanion.insert(
            id: const Value(1),
            name: '山顶',
            latitude: 31,
            longitude: 121,
            travelMode: 'walking',
          ),
        );

    final rows = await database.select(database.recentRouteDestinations).get();

    expect(rows, hasLength(1));
    expect(rows.single.name, '山顶');
    expect(rows.single.travelMode, 'walking');
  });

  test('database rejects invalid coordinates and travel modes', () async {
    await expectLater(
      database
          .into(database.savedPlaces)
          .insert(
            SavedPlacesCompanion.insert(
              id: 'invalid',
              name: '错误机位',
              category: 'viewpoint',
              latitude: 91,
              longitude: 120,
            ),
          ),
      throwsA(anything),
    );
    await expectLater(
      database
          .into(database.recentRouteDestinations)
          .insert(
            RecentRouteDestinationsCompanion.insert(
              id: const Value(1),
              name: '错误路线',
              latitude: 30,
              longitude: 120,
              travelMode: 'flying',
            ),
          ),
      throwsA(anything),
    );
    await expectLater(
      database
          .into(database.recentRouteDestinations)
          .insert(
            RecentRouteDestinationsCompanion.insert(
              id: const Value(2),
              name: '第二条最近路线',
              latitude: 30,
              longitude: 120,
              travelMode: 'walking',
            ),
          ),
      throwsA(anything),
    );
  });
}
