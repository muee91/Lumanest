import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class UserLibraryStore {
  Future<UserLibraryState> read();
  Future<void> write(UserLibraryState state);
}

class DriftUserLibraryStore implements UserLibraryStore {
  DriftUserLibraryStore(this._database, this._preferences);

  static const _key = 'user_library_v1';
  final AppDatabase _database;
  final SharedPreferencesAsync _preferences;

  @override
  Future<UserLibraryState> read() async {
    final persisted = await _readDatabase();
    if (persisted.savedPlaces.isNotEmpty ||
        persisted.recentRoute != null ||
        persisted.savedRoutes.isNotEmpty ||
        persisted.journeys.isNotEmpty ||
        persisted.importedTracks.isNotEmpty ||
        persisted.savedNotes.isNotEmpty) {
      return persisted;
    }

    final raw = await _preferences.getString(_key);
    if (raw == null) return persisted;
    final legacy = _decodeLegacy(raw);
    if (legacy == null) return persisted;

    await _writeDatabase(legacy);
    await _preferences.remove(_key);
    return legacy;
  }

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
                label: row.label,
                emoji: row.emoji,
                category: row.category,
                action: row.actionName,
                detail: row.detail,
                savedAt: row.savedAt.toUtc(),
              ),
            )
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
                label: note.label,
                emoji: note.emoji,
                category: note.category,
                actionName: note.action,
                detail: note.detail,
                savedAt: note.savedAt.toUtc(),
              ),
            );
      }
    });
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

  UserLibraryState? _decodeLegacy(String raw) {
    try {
      final body = jsonDecode(raw);
      if (body is! Map) return null;
      final places = body['savedPlaces'];
      return UserLibraryState(
        savedPlaces: places is List
            ? places
                  .map(SavedPlace.fromJson)
                  .whereType<SavedPlace>()
                  .toList(growable: false)
            : const [],
        recentRoute: SavedRouteDestination.fromJson(body['recentRoute']),
        savedRoutes: const [],
        journeys: const [],
        importedTracks: const [],
      );
    } on Object {
      return null;
    }
  }
}

final userLibraryStoreProvider = Provider<UserLibraryStore>((ref) {
  return DriftUserLibraryStore(
    ref.watch(appDatabaseProvider),
    SharedPreferencesAsync(),
  );
});
