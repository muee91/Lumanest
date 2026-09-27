import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

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

  Future<void> toggleSavedRoute(SavedRouteDestination destination) async {
    final current = await future;
    final id = SavedRoute.idFor(destination);
    final existing = current.savedRoutes.any((route) => route.id == id);
    final routes = existing
        ? current.savedRoutes
              .where((route) => route.id != id)
              .toList(growable: false)
        : [
            SavedRoute.fromDestination(destination, savedAt: DateTime.now()),
            ...current.savedRoutes.where((route) => route.id != id),
          ].take(50).toList(growable: false);
    await _save(current.copyWith(savedRoutes: routes));
  }

  Future<void> deleteSavedRoute(String id) async {
    final current = await future;
    await _save(
      current.copyWith(
        savedRoutes: current.savedRoutes
            .where((route) => route.id != id)
            .toList(growable: false),
      ),
    );
  }

  /// Each category is independently removable so clearing saved places never
  /// erases a user's saved routes or shooting records.
  Future<void> clearSavedPlaces() async {
    final current = await future;
    await _save(current.copyWith(savedPlaces: const []));
  }

  Future<void> clearRecentRoute() async {
    final current = await future;
    await _save(current.copyWith(clearRecentRoute: true));
  }

  Future<void> clearSavedRoutes() async {
    final current = await future;
    await _save(current.copyWith(savedRoutes: const []));
  }

  Future<void> saveInspirationNote({
    required String snapshotId,
    required InspirationNote note,
  }) async {
    final current = await future;
    final saved = SavedInspirationNote.fromNote(
      snapshotId: snapshotId,
      note: note,
      savedAt: DateTime.now(),
    );
    await _save(
      current.copyWith(
        savedNotes: [
          saved,
          ...current.savedNotes.where((candidate) => candidate.id != saved.id),
        ],
      ),
    );
  }

  Future<void> deleteSavedNote(String id) async {
    final current = await future;
    await _save(
      current.copyWith(
        savedNotes: current.savedNotes
            .where((note) => note.id != id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> clearSavedNotes() async {
    final current = await future;
    await _save(current.copyWith(savedNotes: const []));
  }

  Future<void> watchSession({
    required ShootingSession session,
    required String snapshotId,
    String? targetId,
    DateTime? watchedAt,
  }) async {
    final current = await future;
    final watched = WatchedShootingSession.create(
      session: session,
      snapshotId: snapshotId,
      watchedAt: watchedAt ?? DateTime.now(),
      targetId: targetId,
    );
    await _save(
      current.copyWith(
        watchedSessions: [
          watched,
          // A user can watch one window once. Replacing the old target here
          // ensures changing the reviewed target cannot leave two reminders.
          ...current.watchedSessions.where(
            (item) => item.sessionId != watched.sessionId,
          ),
        ],
      ),
    );
  }

  Future<void> unwatchSession(String id) async {
    final current = await future;
    await _save(
      current.copyWith(
        watchedSessions: current.watchedSessions
            .where((item) => item.id != id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> clearWatchedSessions() async {
    final current = await future;
    await _save(current.copyWith(watchedSessions: const []));
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
