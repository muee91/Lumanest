import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class UserLibraryStore {
  Future<UserLibraryState> read();
  Future<void> write(UserLibraryState state);
}

class DriftUserLibraryStore implements UserLibraryStore {
  DriftUserLibraryStore(this._database, this._preferences);

  static const _key = 'user_library_v1';
  final AppDatabase _database;
  final SharedPreferencesAsync _preferences;

  @override
  Future<UserLibraryState> read() async {
    final persisted = await _readDatabase();
    if (persisted.savedPlaces.isNotEmpty || persisted.recentRoute != null) {
      return persisted;
    }

    final raw = await _preferences.getString(_key);
    if (raw == null) return persisted;
    final legacy = _decodeLegacy(raw);
    if (legacy == null) return persisted;

    await _writeDatabase(legacy);
    await _preferences.remove(_key);
    return legacy;
  }

  @override
  Future<void> write(UserLibraryState state) => _writeDatabase(state);

  Future<UserLibraryState> _readDatabase() {
    return _database.transaction(() async {
      final placeQuery = _database.select(_database.savedPlaces)
        ..orderBy([(row) => OrderingTerm.asc(row.id)]);
      final places = await placeQuery.get();
      final route = await _database
          .select(_database.recentRouteDestinations)
          .getSingleOrNull();
      return UserLibraryState(
        savedPlaces: places
            .map(
              (row) => SavedPlace(
                id: row.id,
                name: row.name,
                category: row.category,
                latitude: row.latitude,
                longitude: row.longitude,
              ),
            )
            .toList(growable: false),
        recentRoute: route == null
            ? null
            : SavedRouteDestination(
                name: route.name,
                latitude: route.latitude,
                longitude: route.longitude,
                travelMode: route.travelMode,
              ),
      );
    });
  }

  Future<void> _writeDatabase(UserLibraryState state) {
    return _database.transaction(() async {
      await _database.delete(_database.savedPlaces).go();
      for (final place in state.savedPlaces) {
        await _database
            .into(_database.savedPlaces)
            .insert(
              SavedPlacesCompanion.insert(
                id: place.id,
                name: place.name,
                category: place.category,
                latitude: place.latitude,
                longitude: place.longitude,
              ),
            );
      }

      await _database.delete(_database.recentRouteDestinations).go();
      final route = state.recentRoute;
      if (route != null) {
        await _database
            .into(_database.recentRouteDestinations)
            .insert(
              RecentRouteDestinationsCompanion.insert(
                id: const Value(1),
                name: route.name,
                latitude: route.latitude,
                longitude: route.longitude,
                travelMode: route.travelMode,
              ),
            );
      }
    });
  }

  UserLibraryState? _decodeLegacy(String raw) {
    try {
      final body = jsonDecode(raw);
      if (body is! Map) return null;
      final places = body['savedPlaces'];
      return UserLibraryState(
        savedPlaces: places is List
            ? places
                  .map(SavedPlace.fromJson)
                  .whereType<SavedPlace>()
                  .toList(growable: false)
            : const [],
        recentRoute: SavedRouteDestination.fromJson(body['recentRoute']),
      );
    } on Object {
      return null;
    }
  }
}

final userLibraryStoreProvider = Provider<UserLibraryStore>((ref) {
  return DriftUserLibraryStore(
    ref.watch(appDatabaseProvider),
    SharedPreferencesAsync(),
  );
});
