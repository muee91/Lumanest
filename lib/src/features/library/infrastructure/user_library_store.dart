import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

abstract interface class UserLibraryStore {
  Future<UserLibraryState> read();
  Future<void> write(UserLibraryState state);
}

class DriftUserLibraryStore implements UserLibraryStore {
  DriftUserLibraryStore(this._database);

  final AppDatabase _database;

  @override
  Future<UserLibraryState> read() => _readDatabase();

  @override
  Future<void> write(UserLibraryState state) => _writeDatabase(state);

  Future<UserLibraryState> _readDatabase() {
    return _database.transaction(() async {
      final placeQuery = _database.select(_database.savedPlaces)
        ..orderBy([(row) => OrderingTerm.asc(row.id)]);
      final places = await placeQuery.get();
      final route = await _database
          .select(_database.recentRouteDestinations)
          .getSingleOrNull();
      final savedRouteQuery = _database.select(_database.savedRoutes)
        ..orderBy([(row) => OrderingTerm.desc(row.savedAt)]);
      final savedRoutes = await savedRouteQuery.get();
      final journeyQuery = _database.select(_database.savedJourneys)
        ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]);
      final journeys = await journeyQuery.get();
      final trackQuery = _database.select(_database.importedRouteTracks)
        ..orderBy([(row) => OrderingTerm.desc(row.importedAt)]);
      final tracks = await trackQuery.get();
      final noteQuery = _database.select(_database.savedInspirationNotes)
        ..orderBy([(row) => OrderingTerm.desc(row.savedAt)]);
      final notes = await noteQuery.get();
      final watchedQuery = _database.select(_database.watchedShootingSessions)
        ..orderBy([(row) => OrderingTerm.desc(row.watchedAt)]);
      final watched = await watchedQuery.get();
      final resultQuery = _database.select(_database.shootingSessionResults)
        ..orderBy([(row) => OrderingTerm.desc(row.recordedAt)]);
      final results = await resultQuery.get();
      final packQuery = _database.select(_database.offlinePhotographyPacks)
        ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
      final packs = await packQuery.get();
      return UserLibraryState(
        savedPlaces: places
            .map(
              (row) => SavedPlace(
                id: row.id,
                name: row.name,
                category: row.category,
                latitude: row.latitude,
                longitude: row.longitude,
              ),
            )
            .toList(growable: false),
        recentRoute: route == null
            ? null
            : SavedRouteDestination(
                name: route.name,
                latitude: route.latitude,
                longitude: route.longitude,
                travelMode: route.travelMode,
              ),
        savedRoutes: savedRoutes
            .map(
              (row) => SavedRoute(
                id: row.id,
                destination: SavedRouteDestination(
                  name: row.name,
                  latitude: row.latitude,
                  longitude: row.longitude,
                  travelMode: row.travelMode,
                ),
                savedAt: row.savedAt.toUtc(),
              ),
            )
            .toList(growable: false),
        journeys: journeys
            .map(
              (row) => SavedJourney(
                id: row.id,
                destination: SavedRouteDestination(
                  name: row.name,
                  latitude: row.latitude,
                  longitude: row.longitude,
                  travelMode: row.travelMode,
                ),
                routeKey: row.routeKey,
                startedAt: row.startedAt.toUtc(),
                endedAt: row.endedAt?.toUtc(),
              ),
            )
            .toList(growable: false),
        importedTracks: tracks
            .map(_decodeTrack)
            .whereType<ImportedRouteTrack>()
            .toList(growable: false),
        savedNotes: notes
            .map(
              (row) => SavedInspirationNote(
                id: row.id,
                sourceNoteId: row.sourceNoteId,
                label: row.label,
                emoji: row.emoji,
                category: row.category,
                action: row.actionName,
                detail: row.detail,
                savedAt: row.savedAt.toUtc(),
                authorityUri: _validAuthorityUri(row.authorityUrl),
              ),
            )
            .toList(growable: false),
        watchedSessions: watched
            .map(
              (row) => WatchedShootingSession(
                id: row.id,
                sessionId: row.sessionId,
                snapshotId: row.snapshotId,
                title: row.title,
                kind: ShootingSessionKind.values.byName(row.kind),
                watchedAt: row.watchedAt.toUtc(),
                expiresAt: row.expiresAt.toUtc(),
                targetId: row.targetId,
              ),
            )
            .toList(growable: false),
        sessionResults: results
            .map(
              (row) => ShootingSessionResult(
                id: row.id,
                sessionId: row.sessionId,
                snapshotId: row.snapshotId,
                kind: ShootingSessionKind.values.byName(row.kind),
                outcome: ShootingSessionOutcome.values.byName(row.outcome),
                recordedAt: row.recordedAt.toUtc(),
                reasons: _decodeSessionReasons(row.reasonsJson),
                targetId: row.targetId,
              ),
            )
            .toList(growable: false),
        offlinePhotographyPacks: packs
            .map(_decodeOfflinePhotographyPack)
            .whereType<OfflinePhotographyPack>()
            .toList(growable: false),
      );
    });
  }

  Future<void> _writeDatabase(UserLibraryState state) {
    return _database.transaction(() async {
      await _database.delete(_database.savedPlaces).go();
      for (final place in state.savedPlaces) {
        await _database
            .into(_database.savedPlaces)
            .insert(
              SavedPlacesCompanion.insert(
                id: place.id,
                name: place.name,
                category: place.category,
                latitude: place.latitude,
                longitude: place.longitude,
              ),
            );
      }

      await _database.delete(_database.recentRouteDestinations).go();
      final route = state.recentRoute;
      if (route != null) {
        await _database
            .into(_database.recentRouteDestinations)
            .insert(
              RecentRouteDestinationsCompanion.insert(
                id: const Value(1),
                name: route.name,
                latitude: route.latitude,
                longitude: route.longitude,
                travelMode: route.travelMode,
              ),
            );
      }

      await _database.delete(_database.savedRoutes).go();
      for (final route in state.savedRoutes.take(50)) {
        final destination = route.destination;
        await _database
            .into(_database.savedRoutes)
            .insert(
              SavedRoutesCompanion.insert(
                id: route.id,
                name: destination.name,
                latitude: destination.latitude,
                longitude: destination.longitude,
                travelMode: destination.travelMode,
                savedAt: route.savedAt.toUtc(),
              ),
            );
      }

      await _database.delete(_database.savedJourneys).go();
      for (final journey in state.journeys.take(100)) {
        final destination = journey.destination;
        await _database
            .into(_database.savedJourneys)
            .insert(
              SavedJourneysCompanion.insert(
                id: journey.id,
                name: destination.name,
                latitude: destination.latitude,
                longitude: destination.longitude,
                travelMode: destination.travelMode,
                routeKey: Value(journey.routeKey),
                startedAt: journey.startedAt.toUtc(),
                endedAt: Value(journey.endedAt?.toUtc()),
              ),
            );
      }

      await _database.delete(_database.importedRouteTracks).go();
      for (final track in state.importedTracks) {
        await _database
            .into(_database.importedRouteTracks)
            .insert(
              ImportedRouteTracksCompanion.insert(
                id: track.id,
                name: track.name,
                importedAt: track.importedAt,
                pointsJson: jsonEncode({
                  'points': track.points
                      .map(
                        (point) => {
                          'latitude': point.latitude,
                          'longitude': point.longitude,
                        },
                      )
                      .toList(growable: false),
                  'segmentBreakIndexes': track.segmentBreakIndexes,
                }),
                distanceMeters: track.distanceMeters,
                durationSeconds: track.durationSeconds,
                durationEstimated: track.durationEstimated,
                ascentMeters: Value(track.ascentMeters),
                descentMeters: Value(track.descentMeters),
              ),
            );
      }

      await _database.delete(_database.savedInspirationNotes).go();
      for (final note in state.savedNotes) {
        await _database
            .into(_database.savedInspirationNotes)
            .insert(
              SavedInspirationNotesCompanion.insert(
                id: note.id,
                sourceNoteId: Value(note.sourceNoteId),
                label: note.label,
                emoji: note.emoji,
                category: note.category,
                actionName: note.action,
                detail: note.detail,
                authorityUrl: Value(
                  _validAuthorityUri(note.authorityUri?.toString())?.toString(),
                ),
                savedAt: note.savedAt.toUtc(),
              ),
            );
      }

      await _database.delete(_database.watchedShootingSessions).go();
      for (final watched in state.watchedSessions.take(100)) {
        await _database
            .into(_database.watchedShootingSessions)
            .insert(
              WatchedShootingSessionsCompanion.insert(
                id: watched.id,
                sessionId: watched.sessionId,
                snapshotId: watched.snapshotId,
                title: watched.title,
                kind: watched.kind.name,
                watchedAt: watched.watchedAt.toUtc(),
                expiresAt: watched.expiresAt.toUtc(),
                targetId: Value(watched.targetId),
              ),
            );
      }

      await _database.delete(_database.shootingSessionResults).go();
      for (final result in state.sessionResults.take(200)) {
        await _database
            .into(_database.shootingSessionResults)
            .insert(
              ShootingSessionResultsCompanion.insert(
                id: result.id,
                sessionId: result.sessionId,
                snapshotId: result.snapshotId,
                kind: result.kind.name,
                outcome: result.outcome.name,
                reasonsJson: jsonEncode(
                  result.reasons
                      .map((value) => value.name)
                      .toList(growable: false),
                ),
                recordedAt: result.recordedAt.toUtc(),
                targetId: Value(result.targetId),
              ),
            );
      }

      await _database.delete(_database.offlinePhotographyPacks).go();
      for (final pack in state.offlinePhotographyPacks.take(50)) {
        await _database
            .into(_database.offlinePhotographyPacks)
            .insert(
              OfflinePhotographyPacksCompanion.insert(
                id: pack.id,
                name: pack.name,
                createdAt: pack.createdAt.toUtc(),
                dataTimestamp: pack.dataTimestamp.toUtc(),
                routeJson: Value(
                  pack.route == null ? null : jsonEncode(pack.route!.toJson()),
                ),
                placesJson: jsonEncode(
                  pack.places
                      .map((place) => place.toJson())
                      .toList(growable: false),
                ),
                windowsJson: jsonEncode(
                  pack.windows
                      .map((window) => window.toJson())
                      .toList(growable: false),
                ),
                sessionJson: jsonEncode(pack.sessionSnapshot),
              ),
            );
      }
    });
  }

  OfflinePhotographyPack? _decodeOfflinePhotographyPack(
    OfflinePhotographyPackRow row,
  ) {
    try {
      final route = row.routeJson == null
          ? null
          : SavedRouteDestination.fromJson(jsonDecode(row.routeJson!));
      final rawPlaces = jsonDecode(row.placesJson);
      final rawWindows = jsonDecode(row.windowsJson);
      final rawSession = jsonDecode(row.sessionJson);
      if (rawPlaces is! List || rawWindows is! List || rawSession is! Map) {
        return null;
      }
      final places = rawPlaces
          .map(SavedPlace.fromJson)
          .whereType<SavedPlace>()
          .toList(growable: false);
      if (places.length != rawPlaces.length) return null;
      final windows = rawWindows
          .map(OfflinePhotographyWindow.fromJson)
          .whereType<OfflinePhotographyWindow>()
          .toList(growable: false);
      if (windows.length != rawWindows.length) return null;
      return OfflinePhotographyPack.restore(
        id: row.id,
        name: row.name,
        createdAt: row.createdAt.toUtc(),
        dataTimestamp: row.dataTimestamp.toUtc(),
        route: route,
        places: places,
        windows: windows,
        sessionSnapshot: rawSession.map(
          (key, value) => MapEntry('$key', value),
        ),
      );
    } on Object {
      return null;
    }
  }

  ImportedRouteTrack? _decodeTrack(ImportedRouteTrackRow row) {
    try {
      final rawPoints = jsonDecode(row.pointsJson);
      final pointList = rawPoints is Map ? rawPoints['points'] : rawPoints;
      if (pointList is! List) return null;
      final points = pointList
          .map((raw) {
            if (raw is! Map ||
                raw['latitude'] is! num ||
                raw['longitude'] is! num) {
              throw const FormatException('invalid_track_point');
            }
            return GeoPoint(
              latitude: (raw['latitude'] as num).toDouble(),
              longitude: (raw['longitude'] as num).toDouble(),
            ).validate();
          })
          .toList(growable: false);
      if (points.length < 2) return null;
      final rawBreaks = rawPoints is Map
          ? rawPoints['segmentBreakIndexes']
          : null;
      final breaks = rawBreaks is List
          ? rawBreaks
                .whereType<int>()
                .where((index) => index > 0 && index < points.length)
                .toList(growable: false)
          : const <int>[];
      return ImportedRouteTrack(
        id: row.id,
        name: row.name,
        importedAt: row.importedAt.toUtc(),
        points: points,
        segmentBreakIndexes: breaks,
        distanceMeters: row.distanceMeters,
        durationSeconds: row.durationSeconds,
        durationEstimated: row.durationEstimated,
        ascentMeters: row.ascentMeters,
        descentMeters: row.descentMeters,
      );
    } on Object {
      return null;
    }
  }

  static Uri? _validAuthorityUri(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }

  Set<ShootingSessionOutcomeReason> _decodeSessionReasons(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return decoded
          .whereType<String>()
          .map(ShootingSessionOutcomeReason.values.byName)
          .toSet();
    } on Object {
      return const {};
    }
  }
}

final userLibraryStoreProvider = Provider<UserLibraryStore>((ref) {
  return DriftUserLibraryStore(ref.watch(appDatabaseProvider));
});
