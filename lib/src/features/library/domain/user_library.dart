import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

class SavedInspirationNote {
  const SavedInspirationNote({
    required this.id,
    required this.label,
    required this.emoji,
    required this.category,
    required this.action,
    required this.detail,
    required this.savedAt,
  });

  factory SavedInspirationNote.fromNote({
    required String snapshotId,
    required InspirationNote note,
    required DateTime savedAt,
  }) {
    return SavedInspirationNote(
      id: idFor(snapshotId: snapshotId, noteId: note.id),
      label: note.label,
      emoji: note.emoji,
      category: note.category.name,
      action: note.action.name,
      detail: note.detail,
      savedAt: savedAt.toUtc(),
    );
  }

  static String idFor({required String snapshotId, required String noteId}) =>
      sha256.convert(utf8.encode('$snapshotId\u0000$noteId')).toString();

  final String id;
  final String label;
  final String emoji;
  final String category;
  final String action;
  final String detail;
  final DateTime savedAt;

  String get displayLabel => '$label$emoji';

  ManifestAction? get manifestAction =>
      ManifestAction.values.where((value) => value.name == action).firstOrNull;
}

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
  };

  static SavedPlace? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final category = value['category'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (id is! String ||
        name is! String ||
        category is! String ||
        latitude is! num ||
        longitude is! num) {
      return null;
    }
    return SavedPlace(
      id: id,
      name: name,
      category: category,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}

class SavedRouteDestination {
  const SavedRouteDestination({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.travelMode = 'driving',
  });

  final String name;
  final double latitude;
  final double longitude;
  final String travelMode;

  Map<String, Object?> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'travelMode': travelMode,
  };

  static SavedRouteDestination? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final rawTravelMode = value['travelMode'];
    if (name is! String || latitude is! num || longitude is! num) return null;
    return SavedRouteDestination(
      name: name,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      travelMode: rawTravelMode == 'walking' ? 'walking' : 'driving',
    );
  }
}

class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.destination,
    required this.savedAt,
  });

  factory SavedRoute.fromDestination(
    SavedRouteDestination destination, {
    required DateTime savedAt,
  }) => SavedRoute(
    id: idFor(destination),
    destination: destination,
    savedAt: savedAt.toUtc(),
  );

  static String idFor(SavedRouteDestination destination) => sha256
      .convert(
        utf8.encode(
          '${destination.latitude.toStringAsFixed(6)}\u0000'
          '${destination.longitude.toStringAsFixed(6)}\u0000'
          '${destination.travelMode}',
        ),
      )
      .toString();

  final String id;
  final SavedRouteDestination destination;
  final DateTime savedAt;
}

class UserLibraryState {
  const UserLibraryState({
    this.savedPlaces = const [],
    this.recentRoute,
    this.savedRoutes = const [],
    this.importedTracks = const [],
    this.savedNotes = const [],
  });

  final List<SavedPlace> savedPlaces;
  final SavedRouteDestination? recentRoute;
  final List<SavedRoute> savedRoutes;
  final List<ImportedRouteTrack> importedTracks;
  final List<SavedInspirationNote> savedNotes;

  bool containsPlace(String id) => savedPlaces.any((place) => place.id == id);

  ImportedRouteTrack? importedTrack(String id) =>
      importedTracks.where((track) => track.id == id).firstOrNull;

  bool containsSavedRoute(SavedRouteDestination destination) =>
      savedRoutes.any((route) => route.id == SavedRoute.idFor(destination));

  UserLibraryState copyWith({
    List<SavedPlace>? savedPlaces,
    SavedRouteDestination? recentRoute,
    List<SavedRoute>? savedRoutes,
    List<ImportedRouteTrack>? importedTracks,
    List<SavedInspirationNote>? savedNotes,
  }) => UserLibraryState(
    savedPlaces: List.unmodifiable(savedPlaces ?? this.savedPlaces),
    recentRoute: recentRoute ?? this.recentRoute,
    savedRoutes: List.unmodifiable(savedRoutes ?? this.savedRoutes),
    importedTracks: List.unmodifiable(importedTracks ?? this.importedTracks),
    savedNotes: List.unmodifiable(savedNotes ?? this.savedNotes),
  );
}
