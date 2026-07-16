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

class ActiveImportedTrackConflict implements Exception {
  const ActiveImportedTrackConflict(this.activeJourney);

  final SavedJourney activeJourney;
}

enum PhotographyOpportunityOutcome { shot, missed, skipped }

class WatchedPhotographyOpportunity {
  const WatchedPhotographyOpportunity({
    required this.id,
    required this.opportunityId,
    required this.snapshotId,
    required this.title,
    required this.watchedAt,
    required this.expiresAt,
    this.targetId,
  });

  factory WatchedPhotographyOpportunity.create({
    required String opportunityId,
    required String snapshotId,
    required String title,
    required DateTime watchedAt,
    required DateTime expiresAt,
    String? targetId,
  }) {
    final watched = watchedAt.toUtc();
    final expires = expiresAt.toUtc();
    if (!expires.isAfter(watched)) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after watchedAt',
      );
    }
    return WatchedPhotographyOpportunity(
      id: sha256
          .convert(utf8.encode('$snapshotId\u0000$opportunityId'))
          .toString(),
      opportunityId: opportunityId,
      snapshotId: snapshotId,
      title: title,
      watchedAt: watched,
      expiresAt: expires,
      targetId: targetId,
    );
  }

  final String id;
  final String opportunityId;
  final String snapshotId;
  final String title;
  final DateTime watchedAt;
  final DateTime expiresAt;
  final String? targetId;

  Map<String, Object?> toJson() => {
    'id': id,
    'opportunityId': opportunityId,
    'snapshotId': snapshotId,
    'title': title,
    'watchedAt': watchedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (targetId != null) 'targetId': targetId,
  };
}

class PhotographyOpportunityResult {
  const PhotographyOpportunityResult({
    required this.id,
    required this.opportunityId,
    required this.snapshotId,
    required this.outcome,
    required this.recordedAt,
    this.reason,
    this.targetId,
  });

  factory PhotographyOpportunityResult.record({
    required String opportunityId,
    required String snapshotId,
    required PhotographyOpportunityOutcome outcome,
    required DateTime recordedAt,
    String? reason,
    String? targetId,
  }) {
    final normalizedReason = reason?.trim();
    if (normalizedReason != null && normalizedReason.length > 280) {
      throw ArgumentError.value(
        reason,
        'reason',
        'must contain at most 280 characters',
      );
    }
    final at = recordedAt.toUtc();
    return PhotographyOpportunityResult(
      id: sha256
          .convert(
            utf8.encode(
              '$snapshotId\u0000$opportunityId\u0000${at.microsecondsSinceEpoch}',
            ),
          )
          .toString(),
      opportunityId: opportunityId,
      snapshotId: snapshotId,
      outcome: outcome,
      recordedAt: at,
      reason: normalizedReason?.isEmpty ?? true ? null : normalizedReason,
      targetId: targetId,
    );
  }

  final String id;
  final String opportunityId;
  final String snapshotId;
  final PhotographyOpportunityOutcome outcome;
  final DateTime recordedAt;
  final String? reason;
  final String? targetId;

  Map<String, Object?> toJson() => {
    'id': id,
    'opportunityId': opportunityId,
    'snapshotId': snapshotId,
    'outcome': outcome.name,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    if (reason != null) 'reason': reason,
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
    required this.opportunitySnapshot,
    this.route,
  });

  factory OfflinePhotographyPack.create({
    required String name,
    required DateTime createdAt,
    required DateTime dataTimestamp,
    required List<SavedPlace> places,
    required List<OfflinePhotographyWindow> windows,
    required Map<String, Object?> opportunitySnapshot,
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
    final snapshot = _immutableStructuredMap(opportunitySnapshot);
    final canonical = jsonEncode({
      'name': normalizedName,
      'dataTimestamp': timestamp.toIso8601String(),
      'route': route?.toJson(),
      'places': places.map((place) => place.toJson()).toList(growable: false),
      'windows': windows
          .map((window) => window.toJson())
          .toList(growable: false),
      'opportunitySnapshot': snapshot,
    });
    return OfflinePhotographyPack._(
      id: sha256.convert(utf8.encode(canonical)).toString(),
      name: normalizedName,
      createdAt: created,
      dataTimestamp: timestamp,
      route: route,
      places: List.unmodifiable(places),
      windows: List.unmodifiable(windows),
      opportunitySnapshot: snapshot,
    );
  }

  factory OfflinePhotographyPack.restore({
    required String id,
    required String name,
    required DateTime createdAt,
    required DateTime dataTimestamp,
    required List<SavedPlace> places,
    required List<OfflinePhotographyWindow> windows,
    required Map<String, Object?> opportunitySnapshot,
    SavedRouteDestination? route,
  }) => OfflinePhotographyPack._(
    id: id,
    name: name,
    createdAt: createdAt.toUtc(),
    dataTimestamp: dataTimestamp.toUtc(),
    route: route,
    places: List.unmodifiable(places),
    windows: List.unmodifiable(windows),
    opportunitySnapshot: _immutableStructuredMap(opportunitySnapshot),
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime dataTimestamp;
  final SavedRouteDestination? route;
  final List<SavedPlace> places;
  final List<OfflinePhotographyWindow> windows;
  final Map<String, Object?> opportunitySnapshot;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'dataTimestamp': dataTimestamp.toUtc().toIso8601String(),
    if (route != null) 'route': route!.toJson(),
    'places': places.map((place) => place.toJson()).toList(growable: false),
    'windows': windows.map((window) => window.toJson()).toList(growable: false),
    'opportunitySnapshot': opportunitySnapshot,
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
    this.watchedOpportunities = const [],
    this.opportunityResults = const [],
    this.offlinePhotographyPacks = const [],
  });

  final List<SavedPlace> savedPlaces;
  final SavedRouteDestination? recentRoute;
  final List<SavedRoute> savedRoutes;
  final List<SavedJourney> journeys;
  final List<ImportedRouteTrack> importedTracks;
  final List<SavedInspirationNote> savedNotes;
  final List<WatchedPhotographyOpportunity> watchedOpportunities;
  final List<PhotographyOpportunityResult> opportunityResults;
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
    List<WatchedPhotographyOpportunity>? watchedOpportunities,
    List<PhotographyOpportunityResult>? opportunityResults,
    List<OfflinePhotographyPack>? offlinePhotographyPacks,
  }) => UserLibraryState(
    savedPlaces: List.unmodifiable(savedPlaces ?? this.savedPlaces),
    recentRoute: recentRoute ?? this.recentRoute,
    savedRoutes: List.unmodifiable(savedRoutes ?? this.savedRoutes),
    journeys: List.unmodifiable(journeys ?? this.journeys),
    importedTracks: List.unmodifiable(importedTracks ?? this.importedTracks),
    savedNotes: List.unmodifiable(savedNotes ?? this.savedNotes),
    watchedOpportunities: List.unmodifiable(
      watchedOpportunities ?? this.watchedOpportunities,
    ),
    opportunityResults: List.unmodifiable(
      opportunityResults ?? this.opportunityResults,
    ),
    offlinePhotographyPacks: List.unmodifiable(
      offlinePhotographyPacks ?? this.offlinePhotographyPacks,
    ),
  );

  /// Stable local-only payload for a future user-initiated file export.
  Map<String, Object?> toExportJson() => {
    'format': 'lumanest-local-library-v2',
    'watchedOpportunities': watchedOpportunities
        .map((value) => value.toJson())
        .toList(growable: false),
    'opportunityResults': opportunityResults
        .map((value) => value.toJson())
        .toList(growable: false),
    'offlinePhotographyPacks': offlinePhotographyPacks
        .map((value) => value.toJson())
        .toList(growable: false),
  };
}
