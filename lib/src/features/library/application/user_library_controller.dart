import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

class UserLibraryController extends AsyncNotifier<UserLibraryState> {
  /// Serialises read-modify-write cycles. Two concurrent toggles used to read
  /// the same state, and the later write silently dropped the earlier change —
  /// which the user experiences as a saved place disappearing.
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<UserLibraryState> build() => ref.read(userLibraryStoreProvider).read();

  Future<void> _mutate(
    Future<UserLibraryState> Function(UserLibraryState current) change,
  ) {
    final operation = _writeQueue.then((_) async {
      final current = await future;
      await _save(await change(current));
    });
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> togglePlace(SavedPlace place) => _mutate((current) async {
    final places = [...current.savedPlaces];
    final existing = places.indexWhere((candidate) => candidate.id == place.id);
    if (existing >= 0) {
      places.removeAt(existing);
    } else {
      places.add(place);
    }
    return current.copyWith(savedPlaces: places);
  });

  Future<void> saveRecentRoute(SavedRouteDestination destination) =>
      _mutate((current) async => current.copyWith(recentRoute: destination));

  Future<void> toggleSavedRoute(SavedRouteDestination destination) =>
      _mutate((current) async {
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
        return current.copyWith(savedRoutes: routes);
      });

  Future<void> deleteSavedRoute(String id) => _mutate(
    (current) async => current.copyWith(
      savedRoutes: current.savedRoutes
          .where((route) => route.id != id)
          .toList(growable: false),
    ),
  );

  /// Each category is independently removable so clearing saved places never
  /// erases a user's saved routes or shooting records.
  Future<void> clearSavedPlaces() =>
      _mutate((current) async => current.copyWith(savedPlaces: const []));

  Future<void> clearRecentRoute() =>
      _mutate((current) async => current.copyWith(clearRecentRoute: true));

  Future<void> clearSavedRoutes() =>
      _mutate((current) async => current.copyWith(savedRoutes: const []));

  Future<void> saveInspirationNote({
    required String snapshotId,
    required InspirationNote note,
  }) => _mutate((current) async {
    final saved = SavedInspirationNote.fromNote(
      snapshotId: snapshotId,
      note: note,
      savedAt: DateTime.now(),
    );
    return current.copyWith(
      savedNotes: [
        saved,
        ...current.savedNotes.where((candidate) => candidate.id != saved.id),
      ],
    );
  });

  Future<void> deleteSavedNote(String id) => _mutate(
    (current) async => current.copyWith(
      savedNotes: current.savedNotes
          .where((note) => note.id != id)
          .toList(growable: false),
    ),
  );

  Future<void> clearSavedNotes() =>
      _mutate((current) async => current.copyWith(savedNotes: const []));

  Future<void> watchSession({
    required ShootingSession session,
    required String snapshotId,
    String? targetId,
    DateTime? watchedAt,
  }) => _mutate((current) async {
    final watched = WatchedShootingSession.create(
      session: session,
      snapshotId: snapshotId,
      watchedAt: watchedAt ?? DateTime.now(),
      targetId: targetId,
    );
    return current.copyWith(
      watchedSessions: [
        watched,
        // A user can watch one window once. Replacing the old target here
        // ensures changing the reviewed target cannot leave two reminders.
        ...current.watchedSessions.where(
          (item) => item.sessionId != watched.sessionId,
        ),
      ],
    );
  });

  Future<void> unwatchSession(String id) => _mutate(
    (current) async => current.copyWith(
      watchedSessions: current.watchedSessions
          .where((item) => item.id != id)
          .toList(growable: false),
    ),
  );

  Future<void> clearWatchedSessions() =>
      _mutate((current) async => current.copyWith(watchedSessions: const []));

  Future<void> _save(UserLibraryState value) async {
    state = AsyncData(value);
    await ref.read(userLibraryStoreProvider).write(value);
  }
}

final userLibraryProvider =
    AsyncNotifierProvider<UserLibraryController, UserLibraryState>(
      UserLibraryController.new,
    );
