import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase database;
  late SharedPreferencesAsync preferences;
  late DriftUserLibraryStore store;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    preferences = SharedPreferencesAsync();
    store = DriftUserLibraryStore(database, preferences);
  });

  tearDown(() => database.close());

  test('drift store round-trips the library schema', () async {
    const state = UserLibraryState(
      savedPlaces: [
        SavedPlace(
          id: '1',
          name: '机位',
          category: 'viewpoint',
          latitude: 30,
          longitude: 120,
        ),
      ],
      recentRoute: SavedRouteDestination(
        name: '终点',
        latitude: 31,
        longitude: 121,
        travelMode: 'walking',
      ),
    );

    await store.write(state);
    final restored = await store.read();

    expect(restored.savedPlaces.single.name, '机位');
    expect(restored.recentRoute?.name, '终点');
    expect(restored.recentRoute?.travelMode, 'walking');
  });

  test('a write replaces removed places and clears a removed route', () async {
    await store.write(
      const UserLibraryState(
        savedPlaces: [
          SavedPlace(
            id: 'old',
            name: '旧机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        ],
        recentRoute: SavedRouteDestination(
          name: '旧终点',
          latitude: 31,
          longitude: 121,
        ),
      ),
    );

    await store.write(const UserLibraryState());
    final restored = await store.read();

    expect(restored.savedPlaces, isEmpty);
    expect(restored.recentRoute, isNull);
  });

  test('imports valid legacy JSON once and removes it after commit', () async {
    const legacyKey = 'user_library_v1';
    await preferences.setString(
      legacyKey,
      jsonEncode({
        'savedPlaces': [
          {
            'id': 'legacy',
            'name': '旧收藏',
            'category': 'humanity',
            'latitude': 30,
            'longitude': 120,
          },
        ],
        'recentRoute': {
          'name': '旧路线',
          'latitude': 31,
          'longitude': 121,
          'travelMode': 'walking',
        },
      }),
    );

    final imported = await store.read();

    expect(imported.savedPlaces.single.id, 'legacy');
    expect(imported.recentRoute?.travelMode, 'walking');
    expect(await preferences.getString(legacyKey), isNull);
    expect((await store.read()).savedPlaces.single.id, 'legacy');
  });

  test('malformed legacy JSON is ignored and retained', () async {
    const legacyKey = 'user_library_v1';
    await preferences.setString(legacyKey, '{not-json');

    final restored = await store.read();

    expect(restored.savedPlaces, isEmpty);
    expect(await preferences.getString(legacyKey), '{not-json');
  });

  test('failed legacy import rolls back and retains the source', () async {
    const legacyKey = 'user_library_v1';
    final raw = jsonEncode({
      'savedPlaces': [
        {
          'id': 'invalid',
          'name': '越界机位',
          'category': 'viewpoint',
          'latitude': 91,
          'longitude': 120,
        },
      ],
      'recentRoute': null,
    });
    await preferences.setString(legacyKey, raw);

    await expectLater(store.read(), throwsA(anything));

    expect(await preferences.getString(legacyKey), raw);
    expect(await database.select(database.savedPlaces).get(), isEmpty);
  });

  test('legacy recent routes default to driving mode', () {
    final restored = SavedRouteDestination.fromJson({
      'name': '旧路线',
      'latitude': 31,
      'longitude': 121,
    });

    expect(restored?.travelMode, 'driving');
  });
}
