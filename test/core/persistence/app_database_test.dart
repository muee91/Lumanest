import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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

  test('schema 1 migrates to 3 without losing library data', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp(
      'lumanest-drift-migration-',
    );
    final file = File('${directory.path}/lumanest.sqlite');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
      if (await directory.exists()) await directory.delete();
    });

    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE saved_places (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        CHECK (latitude BETWEEN -90 AND 90),
        CHECK (longitude BETWEEN -180 AND 180)
      )
    ''');
    legacy.execute('''
      CREATE TABLE recent_route_destinations (
        id INTEGER NOT NULL PRIMARY KEY DEFAULT 1,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        travel_mode TEXT NOT NULL,
        CHECK (id = 1),
        CHECK (latitude BETWEEN -90 AND 90),
        CHECK (longitude BETWEEN -180 AND 180),
        CHECK (travel_mode IN ('driving', 'walking'))
      )
    ''');
    legacy.execute(
      "INSERT INTO saved_places VALUES ('legacy', '旧机位', 'viewpoint', 30, 120)",
    );
    legacy.execute(
      "INSERT INTO recent_route_destinations VALUES (1, '旧路线', 31, 121, 'walking')",
    );
    legacy.execute('PRAGMA user_version = 1');
    legacy.close();

    final migrated = AppDatabase(NativeDatabase(file));
    addTearDown(migrated.close);

    expect(
      (await migrated.select(migrated.savedPlaces).get()).single.id,
      'legacy',
    );
    expect(
      (await migrated.select(migrated.recentRouteDestinations).get())
          .single
          .travelMode,
      'walking',
    );
    expect(
      await migrated.select(migrated.profilePreferenceRecords).get(),
      isEmpty,
    );
    expect(await migrated.select(migrated.importedRouteTracks).get(), isEmpty);
  });

  test('schema 2 migrates to 3 and preserves existing preferences', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp(
      'lumanest-drift-v2-migration-',
    );
    final file = File('${directory.path}/lumanest.sqlite');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
      if (await directory.exists()) await directory.delete();
    });

    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE saved_places (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL
      )
    ''');
    legacy.execute('''
      CREATE TABLE recent_route_destinations (
        id INTEGER NOT NULL PRIMARY KEY DEFAULT 1,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        travel_mode TEXT NOT NULL
      )
    ''');
    legacy.execute('''
      CREATE TABLE profile_preferences (
        id INTEGER NOT NULL PRIMARY KEY DEFAULT 1,
        ambient_background_enabled INTEGER NOT NULL,
        reduce_motion INTEGER NOT NULL,
        reduce_flashing INTEGER NOT NULL,
        high_contrast INTEGER NOT NULL,
        ambient_motion_mode TEXT NOT NULL,
        photography_preferences_json TEXT NOT NULL,
        activity_preferences_json TEXT NOT NULL,
        equipment_list TEXT NOT NULL,
        ai_tone TEXT NOT NULL,
        recommendation_intensity REAL NOT NULL
      )
    ''');
    legacy.execute('''
      INSERT INTO profile_preferences VALUES (
        1, 1, 0, 1, 0, 'energySaver', '["风光"]', '["徒步"]',
        '相机', 'balanced', 0.5
      )
    ''');
    legacy.execute('PRAGMA user_version = 2');
    legacy.close();

    final migrated = AppDatabase(NativeDatabase(file));
    addTearDown(migrated.close);

    expect(
      (await migrated.select(migrated.profilePreferenceRecords).get())
          .single
          .ambientMotionMode,
      'energySaver',
    );
    expect(await migrated.select(migrated.importedRouteTracks).get(), isEmpty);
  });
}
