import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';

class UserLibraryController extends AsyncNotifier<UserLibraryState> {
  @override
  Future<UserLibraryState> build() => ref.read(userLibraryStoreProvider).read();

  Future<void> togglePlace(SavedPlace place) async {
    final current = await future;
    final places = [...current.savedPlaces];
    final existing = places.indexWhere((candidate) => candidate.id == place.id);
    if (existing >= 0) {
      places.removeAt(existing);
    } else {
      places.add(place);
    }
    await _save(current.copyWith(savedPlaces: places));
  }

  Future<void> saveRecentRoute(SavedRouteDestination destination) async {
    final current = await future;
    await _save(current.copyWith(recentRoute: destination));
  }

  Future<void> _save(UserLibraryState value) async {
    state = AsyncData(value);
    await ref.read(userLibraryStoreProvider).write(value);
  }
}

final userLibraryProvider =
    AsyncNotifierProvider<UserLibraryController, UserLibraryState>(
      UserLibraryController.new,
    );
