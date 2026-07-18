import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
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

class ActiveImportedTrackConflict implements Exception {
  const ActiveImportedTrackConflict(this.activeJourney);

  final SavedJourney activeJourney;
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
      id: sha256
          .convert(utf8.encode('$snapshotId\u0000${session.id}'))
          .toString(),
      sessionId: session.id,
      snapshotId: snapshotId,
      title: session.title,
      kind: session.kind,
      watchedAt: watched,
      expiresAt: expires,
      targetId: targetId,
    );
  }

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

class ShootingSessionResult {
  ShootingSessionResult({
    required this.id,
    required this.sessionId,
    required this.snapshotId,
    required this.kind,
    required this.outcome,
    required this.recordedAt,
    Iterable<ShootingSessionOutcomeReason> reasons = const [],
    this.targetId,
  }) : reasons = Set.unmodifiable(reasons);

  factory ShootingSessionResult.record({
    required ShootingSession session,
    required String snapshotId,
    required ShootingSessionOutcome outcome,
    required DateTime recordedAt,
    Iterable<ShootingSessionOutcomeReason> reasons = const [],
    String? targetId,
  }) {
    final at = recordedAt.toUtc();
    return ShootingSessionResult(
      id: sha256
          .convert(
            utf8.encode(
              '$snapshotId\u0000${session.id}\u0000${at.microsecondsSinceEpoch}',
            ),
          )
          .toString(),
      sessionId: session.id,
      snapshotId: snapshotId,
      kind: session.kind,
      outcome: outcome,
      recordedAt: at,
      reasons: reasons,
      targetId: targetId,
    );
  }

  final String id;
  final String sessionId;
  final String snapshotId;
  final ShootingSessionKind kind;
  final ShootingSessionOutcome outcome;
  final DateTime recordedAt;
  final Set<ShootingSessionOutcomeReason> reasons;
  final String? targetId;

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'snapshotId': snapshotId,
    'kind': kind.name,
    'outcome': outcome.name,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'reasons': reasons.map((value) => value.name).toList(growable: false),
    if (targetId != null) 'targetId': targetId,
  };
}

class OfflinePhotographyWindow {
  const OfflinePhotographyWindow({
    required this.id,
    required this.label,
    required this.startsAt,
    required this.endsAt,
    this.peakAt,
  });

  final String id;
  final String label;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? peakAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
    if (peakAt != null) 'peakAt': peakAt!.toUtc().toIso8601String(),
  };

  static OfflinePhotographyWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    final startsAt = raw['startsAt'];
    final endsAt = raw['endsAt'];
    final peakAt = raw['peakAt'];
    final start = startsAt is String
        ? DateTime.tryParse(startsAt)?.toUtc()
        : null;
    final end = endsAt is String ? DateTime.tryParse(endsAt)?.toUtc() : null;
    final peak = peakAt == null
        ? null
        : peakAt is String
        ? DateTime.tryParse(peakAt)?.toUtc()
        : null;
    if (id is! String ||
        label is! String ||
        start == null ||
        end == null ||
        !end.isAfter(start) ||
        (peakAt != null && peak == null)) {
      return null;
    }
    return OfflinePhotographyWindow(
      id: id,
      label: label,
      startsAt: start,
      endsAt: end,
      peakAt: peak,
    );
  }
}

class OfflinePhotographyPack {
  OfflinePhotographyPack._({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.dataTimestamp,
    required this.places,
    required this.windows,
    required this.sessionSnapshot,
    this.route,
  });

  factory OfflinePhotographyPack.create({
    required String name,
    required DateTime createdAt,
    required DateTime dataTimestamp,
    required List<SavedPlace> places,
    required List<OfflinePhotographyWindow> windows,
    required Map<String, Object?> sessionSnapshot,
    SavedRouteDestination? route,
  }) {
    final created = createdAt.toUtc();
    final timestamp = dataTimestamp.toUtc();
    if (timestamp.isAfter(created)) {
      throw ArgumentError.value(
        dataTimestamp,
        'dataTimestamp',
        'must not be after createdAt',
      );
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 160) {
      throw ArgumentError.value(
        name,
        'name',
        'must contain 1 to 160 characters',
      );
    }
    final snapshot = _immutableStructuredMap(sessionSnapshot);
    final canonical = jsonEncode({
      'name': normalizedName,
      'dataTimestamp': timestamp.toIso8601String(),
      'route': route?.toJson(),
      'places': places.map((place) => place.toJson()).toList(growable: false),
      'windows': windows
          .map((window) => window.toJson())
          .toList(growable: false),
      'sessionSnapshot': snapshot,
    });
    return OfflinePhotographyPack._(
      id: sha256.convert(utf8.encode(canonical)).toString(),
      name: normalizedName,
      createdAt: created,
      dataTimestamp: timestamp,
      route: route,
      places: List.unmodifiable(places),
      windows: List.unmodifiable(windows),
      sessionSnapshot: snapshot,
    );
  }

  factory OfflinePhotographyPack.restore({
    required String id,
    required String name,
    required DateTime createdAt,
    required DateTime dataTimestamp,
    required List<SavedPlace> places,
    required List<OfflinePhotographyWindow> windows,
    required Map<String, Object?> sessionSnapshot,
    SavedRouteDestination? route,
  }) => OfflinePhotographyPack._(
    id: id,
    name: name,
    createdAt: createdAt.toUtc(),
    dataTimestamp: dataTimestamp.toUtc(),
    route: route,
    places: List.unmodifiable(places),
    windows: List.unmodifiable(windows),
    sessionSnapshot: _immutableStructuredMap(sessionSnapshot),
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime dataTimestamp;
  final SavedRouteDestination? route;
  final List<SavedPlace> places;
  final List<OfflinePhotographyWindow> windows;
  final Map<String, Object?> sessionSnapshot;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'dataTimestamp': dataTimestamp.toUtc().toIso8601String(),
    if (route != null) 'route': route!.toJson(),
    'places': places.map((place) => place.toJson()).toList(growable: false),
    'windows': windows.map((window) => window.toJson()).toList(growable: false),
    'sessionSnapshot': sessionSnapshot,
  };
}

Map<String, Object?> _immutableStructuredMap(Map<String, Object?> value) {
  final encoded = jsonEncode(value);
  final decoded = jsonDecode(encoded);
  if (decoded is! Map) throw const FormatException('invalid_structured_map');
  return Map.unmodifiable(
    decoded.map((key, item) => MapEntry('$key', _freezeJson(item))),
  );
}

Object? _freezeJson(Object? value) => switch (value) {
  Map() => Map.unmodifiable(
    value.map((key, item) => MapEntry('$key', _freezeJson(item))),
  ),
  List() => List.unmodifiable(value.map(_freezeJson)),
  _ => value,
};

class UserLibraryState {
  const UserLibraryState({
    this.savedPlaces = const [],
    this.recentRoute,
    this.savedRoutes = const [],
    this.journeys = const [],
    this.importedTracks = const [],
    this.savedNotes = const [],
    this.watchedSessions = const [],
    this.sessionResults = const [],
    this.offlinePhotographyPacks = const [],
  });

  final List<SavedPlace> savedPlaces;
  final SavedRouteDestination? recentRoute;
  final List<SavedRoute> savedRoutes;
  final List<SavedJourney> journeys;
  final List<ImportedRouteTrack> importedTracks;
  final List<SavedInspirationNote> savedNotes;
  final List<WatchedShootingSession> watchedSessions;
  final List<ShootingSessionResult> sessionResults;
  final List<OfflinePhotographyPack> offlinePhotographyPacks;

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
    List<WatchedShootingSession>? watchedSessions,
    List<ShootingSessionResult>? sessionResults,
    List<OfflinePhotographyPack>? offlinePhotographyPacks,
  }) => UserLibraryState(
    savedPlaces: List.unmodifiable(savedPlaces ?? this.savedPlaces),
    recentRoute: recentRoute ?? this.recentRoute,
    savedRoutes: List.unmodifiable(savedRoutes ?? this.savedRoutes),
    journeys: List.unmodifiable(journeys ?? this.journeys),
    importedTracks: List.unmodifiable(importedTracks ?? this.importedTracks),
    savedNotes: List.unmodifiable(savedNotes ?? this.savedNotes),
    watchedSessions: List.unmodifiable(watchedSessions ?? this.watchedSessions),
    sessionResults: List.unmodifiable(sessionResults ?? this.sessionResults),
    offlinePhotographyPacks: List.unmodifiable(
      offlinePhotographyPacks ?? this.offlinePhotographyPacks,
    ),
  );

  /// Stable local-only payload for a future user-initiated file export.
  Map<String, Object?> toExportJson() => {
    'format': 'lumanest-local-library-v4',
    'watchedSessions': watchedSessions
        .map((value) => value.toJson())
        .toList(growable: false),
    'sessionResults': sessionResults
        .map((value) => value.toJson())
        .toList(growable: false),
    'offlinePhotographyPacks': offlinePhotographyPacks
        .map((value) => value.toJson())
        .toList(growable: false),
  };
}
