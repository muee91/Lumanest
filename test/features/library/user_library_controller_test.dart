import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';

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
}

class _FakeStore implements UserLibraryStore {
  _FakeStore(this.value);
  UserLibraryState value;

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}
