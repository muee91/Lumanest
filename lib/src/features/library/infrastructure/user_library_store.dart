import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class UserLibraryStore {
  Future<UserLibraryState> read();
  Future<void> write(UserLibraryState state);
}

class SharedPreferencesUserLibraryStore implements UserLibraryStore {
  SharedPreferencesUserLibraryStore(this._preferences);

  static const _key = 'user_library_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<UserLibraryState> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return const UserLibraryState();
    try {
      final body = jsonDecode(raw);
      if (body is! Map) return const UserLibraryState();
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
    } on FormatException {
      return const UserLibraryState();
    }
  }

  @override
  Future<void> write(UserLibraryState state) {
    return _preferences.setString(
      _key,
      jsonEncode({
        'savedPlaces': state.savedPlaces
            .map((place) => place.toJson())
            .toList(),
        'recentRoute': state.recentRoute?.toJson(),
      }),
    );
  }
}

final userLibraryStoreProvider = Provider<UserLibraryStore>((ref) {
  return SharedPreferencesUserLibraryStore(SharedPreferencesAsync());
});
