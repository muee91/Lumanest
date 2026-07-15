import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

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

  Future<void> saveImportedTrack(ImportedRouteTrack track) async {
    final current = await future;
    final tracks = [
      track,
      ...current.importedTracks.where((candidate) => candidate.id != track.id),
    ];
    await _save(current.copyWith(importedTracks: tracks));
  }

  Future<void> deleteImportedTrack(String id) async {
    final current = await future;
    await _save(
      current.copyWith(
        importedTracks: current.importedTracks
            .where((track) => track.id != id)
            .toList(growable: false),
      ),
    );
  }

  /// Each category is independently removable so clearing saved places never
  /// erases a user's route history or imported GPX tracks.
  Future<void> clearSavedPlaces() async {
    final current = await future;
    await _save(current.copyWith(savedPlaces: const []));
  }

  Future<void> clearRecentRoute() async {
    final current = await future;
    await _save(
      UserLibraryState(
        savedPlaces: current.savedPlaces,
        importedTracks: current.importedTracks,
        savedNotes: current.savedNotes,
      ),
    );
  }

  Future<void> clearImportedTracks() async {
    final current = await future;
    await _save(current.copyWith(importedTracks: const []));
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

  Future<void> _save(UserLibraryState value) async {
    state = AsyncData(value);
    await ref.read(userLibraryStoreProvider).write(value);
  }
}

final userLibraryProvider =
    AsyncNotifierProvider<UserLibraryController, UserLibraryState>(
      UserLibraryController.new,
    );
