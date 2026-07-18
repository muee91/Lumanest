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
    expect(rows.single.travelMode, 'walking');
  });

  test('current schema enforces route and session constraints', () async {
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
          .into(database.watchedShootingSessions)
          .insert(
            WatchedShootingSessionsCompanion.insert(
              id: List.filled(64, 'a').join(),
              sessionId: 'session-1',
              snapshotId: 'snapshot-1',
              title: '会话',
              kind: 'unknown',
              watchedAt: DateTime.utc(2026, 7, 18, 8),
              expiresAt: DateTime.utc(2026, 7, 18, 9),
            ),
          ),
      throwsA(anything),
    );
  });

  test('older database versions are discarded instead of migrated', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp(
      'lumanest-clean-schema-',
    );
    final file = File('${directory.path}/lumanest.sqlite');
    addTearDown(() async {
      if (await file.exists()) await file.delete();
      if (await directory.exists()) await directory.delete();
    });

    final old = sqlite.sqlite3.open(file.path);
    old.execute('''
      CREATE TABLE saved_places (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL
      )
    ''');
    old.execute(
      "INSERT INTO saved_places VALUES ('old', '旧机位', 'viewpoint', 30, 120)",
    );
    old.execute('PRAGMA user_version = 1');
    old.close();

    final current = AppDatabase(NativeDatabase(file));
    addTearDown(current.close);

    expect(await current.select(current.savedPlaces).get(), isEmpty);
    expect(
      await current.select(current.watchedShootingSessions).get(),
      isEmpty,
    );
    expect(await current.select(current.shootingSessionResults).get(), isEmpty);
    expect(current.schemaVersion, 14);
  });

  test('base region is a replaceable local singleton', () async {
    await database
        .into(database.baseRegions)
        .insert(
          BaseRegionsCompanion.insert(
            id: const Value(1),
            name: '杭州',
            latitude: 30.2741,
            longitude: 120.1551,
            selectedAt: DateTime.utc(2026, 7, 18),
          ),
        );
    await database
        .into(database.baseRegions)
        .insertOnConflictUpdate(
          BaseRegionsCompanion.insert(
            id: const Value(1),
            name: '黄山',
            address: const Value('安徽'),
            latitude: 30.133,
            longitude: 118.167,
            selectedAt: DateTime.utc(2026, 7, 18, 1),
          ),
        );

    final rows = await database.select(database.baseRegions).get();

    expect(rows.single.name, '黄山');
    expect(rows.single.address, '安徽');
  });
}
