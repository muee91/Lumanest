import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

class SavedInspirationNote {
  const SavedInspirationNote({
    required this.id,
    required this.sourceNoteId,
    required this.label,
    required this.emoji,
    required this.category,
    required this.action,
    required this.detail,
    required this.savedAt,
    this.authorityUri,
  });

  factory SavedInspirationNote.fromNote({
    required String snapshotId,
    required InspirationNote note,
    required DateTime savedAt,
  }) {
    return SavedInspirationNote(
      id: idFor(snapshotId: snapshotId, noteId: note.id),
      sourceNoteId: note.id,
      label: note.label,
      emoji: note.emoji,
      category: note.category.name,
      action: note.action.name,
      detail: note.detail,
      savedAt: savedAt.toUtc(),
      authorityUri: _validAuthorityUri(note.authorityUri),
    );
  }

  static String idFor({required String snapshotId, required String noteId}) =>
      sha256.convert(utf8.encode('$snapshotId\u0000$noteId')).toString();

  final String id;
  final String sourceNoteId;
  final String label;
  final String emoji;
  final String category;
  final String action;
  final String detail;
  final DateTime savedAt;
  final Uri? authorityUri;

  String get displayLabel => '$label$emoji';

  ManifestAction? get manifestAction =>
      ManifestAction.values.where((value) => value.name == action).firstOrNull;

  ManifestItem? get manifestItem {
    final resolvedAction = manifestAction;
    final safeAuthorityUri = _validAuthorityUri(authorityUri);
    if (resolvedAction == null ||
        resolvedAction == ManifestAction.openAuthority &&
            safeAuthorityUri == null) {
      return null;
    }
    return ManifestItem(
      id: sourceNoteId,
      title: displayLabel,
      action: resolvedAction,
      authorityUri: resolvedAction == ManifestAction.openAuthority
          ? safeAuthorityUri
          : null,
    );
  }

  static Uri? _validAuthorityUri(Uri? value) =>
      value != null && value.scheme == 'https' && value.host.isNotEmpty
      ? value
      : null;
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

class SavedJourney {
  const SavedJourney({
    required this.id,
    required this.destination,
    required this.startedAt,
    this.endedAt,
    this.routeKey,
  });

  factory SavedJourney.start(
    SavedRouteDestination destination, {
    required DateTime startedAt,
    String? routeKey,
  }) {
    final start = startedAt.toUtc();
    return SavedJourney(
      id: sha256
          .convert(
            utf8.encode(
              '${SavedRoute.idFor(destination)}\u0000'
              '${routeKey ?? ''}\u0000${start.microsecondsSinceEpoch}',
            ),
          )
          .toString(),
      destination: destination,
      startedAt: start,
      routeKey: routeKey,
    );
  }

  final String id;
  final SavedRouteDestination destination;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? routeKey;

  bool get isActive => endedAt == null;

  bool matches(SavedRouteDestination value, {String? routeKey}) =>
      SavedRoute.idFor(destination) == SavedRoute.idFor(value) &&
      this.routeKey == routeKey;

  SavedJourney end(DateTime value) => SavedJourney(
    id: id,
    destination: destination,
    startedAt: startedAt,
    endedAt: value.toUtc().isBefore(startedAt) ? startedAt : value.toUtc(),
    routeKey: routeKey,
  );
}

class ActiveJourneyConflict implements Exception {
  const ActiveJourneyConflict(this.activeJourney);

  final SavedJourney activeJourney;
}

class UserLibraryState {
  const UserLibraryState({
    this.savedPlaces = const [],
    this.recentRoute,
    this.savedRoutes = const [],
    this.journeys = const [],
    this.importedTracks = const [],
    this.savedNotes = const [],
  });

  final List<SavedPlace> savedPlaces;
  final SavedRouteDestination? recentRoute;
  final List<SavedRoute> savedRoutes;
  final List<SavedJourney> journeys;
  final List<ImportedRouteTrack> importedTracks;
  final List<SavedInspirationNote> savedNotes;

  bool containsPlace(String id) => savedPlaces.any((place) => place.id == id);

  ImportedRouteTrack? importedTrack(String id) =>
      importedTracks.where((track) => track.id == id).firstOrNull;

  bool containsSavedRoute(SavedRouteDestination destination) =>
      savedRoutes.any((route) => route.id == SavedRoute.idFor(destination));

  SavedJourney? get activeJourney =>
      journeys.where((journey) => journey.isActive).firstOrNull;

  UserLibraryState copyWith({
    List<SavedPlace>? savedPlaces,
    SavedRouteDestination? recentRoute,
    List<SavedRoute>? savedRoutes,
    List<SavedJourney>? journeys,
    List<ImportedRouteTrack>? importedTracks,
    List<SavedInspirationNote>? savedNotes,
  }) => UserLibraryState(
    savedPlaces: List.unmodifiable(savedPlaces ?? this.savedPlaces),
    recentRoute: recentRoute ?? this.recentRoute,
    savedRoutes: List.unmodifiable(savedRoutes ?? this.savedRoutes),
    journeys: List.unmodifiable(journeys ?? this.journeys),
    importedTracks: List.unmodifiable(importedTracks ?? this.importedTracks),
    savedNotes: List.unmodifiable(savedNotes ?? this.savedNotes),
  );
}
