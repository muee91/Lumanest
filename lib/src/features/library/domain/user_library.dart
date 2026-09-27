import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';

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
        resolvedAction == ManifestAction.openAstronomyDetail &&
            safeAuthorityUri == null) {
      return null;
    }
    return ManifestItem(
      id: sourceNoteId,
      title: displayLabel,
      action: resolvedAction,
      authorityUri: resolvedAction == ManifestAction.openAstronomyDetail
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
    this.coordinateSystem = CoordinateSystem.wgs84,
  });

  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final CoordinateSystem coordinateSystem;

  GeoPoint get point => GeoPoint(
    latitude: latitude,
    longitude: longitude,
    coordinateSystem: coordinateSystem,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
    'coordinateSystem': coordinateSystem.name,
  };

  static SavedPlace? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final category = value['category'];
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final coordinateSystem = CoordinateSystem.values
        .where((item) => item.name == value['coordinateSystem'])
        .firstOrNull;
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
      // Old exports did not carry a coordinate contract. Preserve them as
      // unknown instead of silently treating map coordinates as WGS-84.
      coordinateSystem: coordinateSystem ?? CoordinateSystem.unknown,
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

class WatchedShootingSession {
  const WatchedShootingSession({
    required this.id,
    required this.sessionId,
    required this.snapshotId,
    required this.title,
    required this.kind,
    required this.watchedAt,
    required this.expiresAt,
    this.targetId,
  });

  factory WatchedShootingSession.create({
    required ShootingSession session,
    required String snapshotId,
    required DateTime watchedAt,
    String? targetId,
  }) {
    final watched = watchedAt.toUtc();
    final expires = session.endsAt.toUtc();
    if (!expires.isAfter(watched)) {
      throw ArgumentError.value(
        session.endsAt,
        'session.endsAt',
        'must be after watchedAt',
      );
    }
    return WatchedShootingSession(
      id: idFor(sessionId: session.id, targetId: targetId),
      sessionId: session.id,
      snapshotId: snapshotId,
      title: session.title,
      kind: session.kind,
      watchedAt: watched,
      expiresAt: expires,
      targetId: targetId,
    );
  }

  /// A watch is the user's intent for one session/target window. Snapshot
  /// identity records which evidence created it, but must not create another
  /// watch for the same window after a refresh.
  static String idFor({required String sessionId, String? targetId}) => sha256
      .convert(utf8.encode('$sessionId\u0000${targetId ?? ''}'))
      .toString();

  final String id;
  final String sessionId;
  final String snapshotId;
  final String title;
  final ShootingSessionKind kind;
  final DateTime watchedAt;
  final DateTime expiresAt;
  final String? targetId;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'snapshotId': snapshotId,
    'title': title,
    'kind': kind.name,
    'watchedAt': watchedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (targetId != null) 'targetId': targetId,
  };
}

class UserLibraryState {
  const UserLibraryState({
    this.savedPlaces = const [],
    this.recentRoute,
    this.savedRoutes = const [],
    this.savedNotes = const [],
    this.watchedSessions = const [],
  });

  final List<SavedPlace> savedPlaces;
  final SavedRouteDestination? recentRoute;
  final List<SavedRoute> savedRoutes;
  final List<SavedInspirationNote> savedNotes;
  final List<WatchedShootingSession> watchedSessions;

  bool containsPlace(String id) => savedPlaces.any((place) => place.id == id);

  bool containsSavedRoute(SavedRouteDestination destination) =>
      savedRoutes.any((route) => route.id == SavedRoute.idFor(destination));

  UserLibraryState copyWith({
    List<SavedPlace>? savedPlaces,
    SavedRouteDestination? recentRoute,
    bool clearRecentRoute = false,
    List<SavedRoute>? savedRoutes,
    List<SavedInspirationNote>? savedNotes,
    List<WatchedShootingSession>? watchedSessions,
  }) => UserLibraryState(
    savedPlaces: List.unmodifiable(savedPlaces ?? this.savedPlaces),
    recentRoute: clearRecentRoute ? null : (recentRoute ?? this.recentRoute),
    savedRoutes: List.unmodifiable(savedRoutes ?? this.savedRoutes),
    savedNotes: List.unmodifiable(savedNotes ?? this.savedNotes),
    watchedSessions: List.unmodifiable(watchedSessions ?? this.watchedSessions),
  );

  /// Stable local-only payload for a future user-initiated file export.
  Map<String, Object?> toExportJson() => {
    'format': 'lumanest-local-library-v4',
    'watchedSessions': watchedSessions
        .map((value) => value.toJson())
        .toList(growable: false),
  };
}
