import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
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
    final state = UserLibraryState(
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
      savedRoutes: [
        SavedRoute.fromDestination(
          const SavedRouteDestination(
            name: '湖岸收藏路线',
            latitude: 30.2,
            longitude: 120.1,
          ),
          savedAt: DateTime.utc(2026, 7, 15, 8),
        ),
      ],
      importedTracks: [
        ImportedRouteTrack(
          id: 'track-1',
          name: '本地徒步',
          importedAt: DateTime.utc(2026, 7, 15),
          points: const [
            GeoPoint(latitude: 30, longitude: 120),
            GeoPoint(latitude: 30.1, longitude: 120.1),
            GeoPoint(latitude: 31, longitude: 121),
            GeoPoint(latitude: 31.1, longitude: 121.1),
          ],
          segmentBreakIndexes: const [2],
          distanceMeters: 1200,
          durationSeconds: 900,
          durationEstimated: false,
          ascentMeters: 80,
          descentMeters: 20,
        ),
      ],
      savedNotes: [
        SavedInspirationNote.fromNote(
          snapshotId: 'snapshot-1',
          note: const InspirationNote(
            id: 'reflection',
            label: '找倒影',
            emoji: '🪞',
            category: InspirationCategory.place,
            action: ManifestAction.openExplore,
            detail: '去湖岸找一段干净的水面。',
            priority: 100,
            ttl: Duration(minutes: 30),
          ),
          savedAt: DateTime.utc(2026, 7, 15),
        ),
      ],
    );

    await store.write(state);
    final restored = await store.read();

    expect(restored.savedPlaces.single.name, '机位');
    expect(restored.recentRoute?.name, '终点');
    expect(restored.recentRoute?.travelMode, 'walking');
    expect(restored.savedRoutes.single.destination.name, '湖岸收藏路线');
    expect(restored.savedRoutes.single.savedAt, DateTime.utc(2026, 7, 15, 8));
    expect(restored.importedTracks.single.name, '本地徒步');
    expect(restored.importedTracks.single.points.last.longitude, 121.1);
    expect(restored.importedTracks.single.segmentBreakIndexes, [2]);
    expect(restored.importedTracks.single.ascentMeters, 80);
    expect(restored.savedNotes.single.displayLabel, '找倒影🪞');
    expect(
      restored.savedNotes.single.manifestAction,
      ManifestAction.openExplore,
    );
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
    expect(restored.savedRoutes, isEmpty);
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
