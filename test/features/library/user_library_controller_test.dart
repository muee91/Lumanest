import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

void main() {
  test('restores, toggles and persists saved places', () async {
    final store = _FakeStore(
      const UserLibraryState(
        savedPlaces: [
          SavedPlace(
            id: 'a',
            name: '湖岸机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final restored = await container.read(userLibraryProvider.future);
    expect(restored.savedPlaces.single.id, 'a');

    await container
        .read(userLibraryProvider.notifier)
        .togglePlace(
          const SavedPlace(
            id: 'b',
            name: '古镇',
            category: 'humanity',
            latitude: 31,
            longitude: 121,
          ),
        );
    expect(
      store.value.savedPlaces.map((place) => place.id),
      containsAll(['a', 'b']),
    );

    await container
        .read(userLibraryProvider.notifier)
        .togglePlace(store.value.savedPlaces.first);
    expect(
      store.value.savedPlaces.map((place) => place.id),
      isNot(contains('a')),
    );
  });

  test('persists only the latest route destination', () async {
    final store = _FakeStore(const UserLibraryState());
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(userLibraryProvider.future);

    await container
        .read(userLibraryProvider.notifier)
        .saveRecentRoute(
          const SavedRouteDestination(
            name: '雪山机位',
            latitude: 30,
            longitude: 101,
            travelMode: 'walking',
          ),
        );

    expect(store.value.recentRoute?.name, '雪山机位');
    expect(store.value.recentRoute?.travelMode, 'walking');
  });

  test('persists and deletes an imported GPX track', () async {
    final store = _FakeStore(const UserLibraryState());
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    const points = [
      GeoPoint(latitude: 30, longitude: 120),
      GeoPoint(latitude: 30.1, longitude: 120.1),
    ];
    final track = ImportedRouteTrack(
      id: 'track-1',
      name: '导入徒步',
      importedAt: DateTime.utc(2026, 7, 15),
      points: points,
      distanceMeters: 1000,
      durationSeconds: 600,
      durationEstimated: false,
    );

    await container.read(userLibraryProvider.notifier).saveImportedTrack(track);
    expect(store.value.importedTracks.single.id, 'track-1');

    await container
        .read(userLibraryProvider.notifier)
        .deleteImportedTrack('track-1');
    expect(store.value.importedTracks, isEmpty);
  });

  test('clears only the selected local library category', () async {
    final track = ImportedRouteTrack(
      id: 'track-1',
      name: '导入徒步',
      importedAt: DateTime.utc(2026, 7, 15),
      points: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.1, longitude: 120.1),
      ],
      distanceMeters: 1000,
      durationSeconds: 600,
      durationEstimated: false,
    );
    final store = _FakeStore(
      UserLibraryState(
        savedPlaces: const [
          SavedPlace(
            id: 'place-1',
            name: '湖岸机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        ],
        recentRoute: const SavedRouteDestination(
          name: '山路',
          latitude: 31,
          longitude: 121,
        ),
        importedTracks: [track],
      ),
    );
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(userLibraryProvider.future);
    final controller = container.read(userLibraryProvider.notifier);

    await controller.clearSavedPlaces();
    expect(store.value.savedPlaces, isEmpty);
    expect(store.value.recentRoute, isNotNull);
    expect(store.value.importedTracks, hasLength(1));

    await controller.clearRecentRoute();
    expect(store.value.recentRoute, isNull);
    expect(store.value.importedTracks, hasLength(1));

    await controller.clearImportedTracks();
    expect(store.value.importedTracks, isEmpty);
  });
}

class _FakeStore implements UserLibraryStore {
  _FakeStore(this.value);
  UserLibraryState value;

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}
