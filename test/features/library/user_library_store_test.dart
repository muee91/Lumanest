import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('shared preferences store round-trips the library schema', () async {
    final store = SharedPreferencesUserLibraryStore(SharedPreferencesAsync());
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

  test('legacy recent routes default to driving mode', () {
    final restored = SavedRouteDestination.fromJson({
      'name': '旧路线',
      'latitude': 31,
      'longitude': 121,
    });

    expect(restored?.travelMode, 'driving');
  });
}
