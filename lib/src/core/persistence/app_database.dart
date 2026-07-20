import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('SavedPlaceRow')
class SavedPlaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
  ];
}

@DataClassName('RecentRouteDestinationRow')
class RecentRouteDestinations extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get travelMode => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (id = 1)',
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
    "CHECK (travel_mode IN ('driving', 'walking'))",
  ];
}

@DataClassName('SavedRouteRow')
class SavedRoutes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get travelMode => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) = 64)',
    'CHECK (length(name) BETWEEN 1 AND 160)',
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
    "CHECK (travel_mode IN ('driving', 'walking'))",
  ];
}

@DataClassName('SavedJourneyRow')
class SavedJourneys extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get travelMode => text()();
  TextColumn get routeKey => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) = 64)',
    'CHECK (length(name) BETWEEN 1 AND 160)',
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
    "CHECK (travel_mode IN ('driving', 'walking'))",
    'CHECK (route_key IS NULL OR length(route_key) BETWEEN 1 AND 160)',
    'CHECK (ended_at IS NULL OR ended_at >= started_at)',
  ];
}

@DataClassName('ImportedRouteTrackRow')
class ImportedRouteTracks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get pointsJson => text()();
  IntColumn get distanceMeters => integer()();
  IntColumn get durationSeconds => integer()();
  BoolColumn get durationEstimated => boolean()();
  IntColumn get ascentMeters => integer().nullable()();
  IntColumn get descentMeters => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(name) BETWEEN 1 AND 120)',
    'CHECK (distance_meters > 0)',
    'CHECK (duration_seconds > 0)',
    'CHECK (ascent_meters IS NULL OR ascent_meters >= 0)',
    'CHECK (descent_meters IS NULL OR descent_meters >= 0)',
  ];
}

@DataClassName('ProfilePreferenceRow')
class ProfilePreferenceRecords extends Table {
  @override
  String get tableName => 'profile_preferences';

  IntColumn get id => integer().withDefault(const Constant(1))();
  BoolColumn get ambientBackgroundEnabled => boolean()();
  BoolColumn get reduceMotion => boolean()();
  BoolColumn get reduceFlashing => boolean()();
  BoolColumn get highContrast => boolean()();
  TextColumn get ambientMotionMode => text()();
  TextColumn get photographyPreferencesJson => text()();
  TextColumn get activityPreferencesJson => text()();
  TextColumn get equipmentList => text()();
  TextColumn get aiTone => text()();
  RealColumn get recommendationIntensity => real()();
  BoolColumn get shareAnonymousPhotographyFeedback =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (id = 1)',
    "CHECK (ambient_motion_mode IN ('full', 'energySaver', 'staticColor'))",
    "CHECK (ai_tone IN ('concise', 'balanced', 'detailed'))",
    'CHECK (recommendation_intensity BETWEEN 0 AND 1)',
  ];
}

/// The user's explicitly selected local base region. This is intentionally
/// separate from appearance/preferences so location-derived data has a clear,
/// independently deletable owner.
@DataClassName('BaseRegionRow')
class BaseRegions extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get selectedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (id = 1)',
    'CHECK (length(name) BETWEEN 1 AND 160)',
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
  ];
}

/// v5 context entries are cached independently from the environment snapshot.
/// The payload is already validated JSON; expiry and revision are indexed so
/// partial refreshes can replace one entry without rewriting the snapshot.
class EntryCacheRecords extends Table {
  TextColumn get id => text()();
  IntColumn get revision => integer()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get writtenAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CompositionCacheRecords extends Table {
  TextColumn get id => text()();
  IntColumn get revision => integer()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get writtenAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The most recent explicit map/search selection. It is local-only and can be
/// cleared independently from the user's long-term base region.
@DataClassName('ManualLocationRow')
class ManualLocations extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get selectedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (id = 1)',
    'CHECK (length(name) BETWEEN 1 AND 160)',
    'CHECK (latitude BETWEEN -90 AND 90)',
    'CHECK (longitude BETWEEN -180 AND 180)',
  ];
}

@DataClassName('SavedInspirationNoteRow')
class SavedInspirationNotes extends Table {
  TextColumn get id => text()();
  TextColumn get sourceNoteId =>
      text().withDefault(const Constant('saved-note'))();
  TextColumn get label => text()();
  TextColumn get emoji => text()();
  TextColumn get category => text()();
  TextColumn get actionName => text()();
  TextColumn get detail => text()();
  TextColumn get authorityUrl => text().nullable()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) BETWEEN 1 AND 100)',
    'CHECK (length(source_note_id) BETWEEN 1 AND 160)',
    'CHECK (length(label) BETWEEN 1 AND 40)',
    'CHECK (length(emoji) BETWEEN 1 AND 16)',
    'CHECK (length(category) BETWEEN 1 AND 40)',
    'CHECK (length(action_name) BETWEEN 1 AND 60)',
    'CHECK (length(detail) BETWEEN 1 AND 500)',
    'CHECK (authority_url IS NULL OR length(authority_url) BETWEEN 1 AND 500)',
  ];
}

@DataClassName('WildlifeMapLayerCacheRow')
class WildlifeMapLayerCaches extends Table {
  TextColumn get id => text()();
  RealColumn get centerLatitude => real()();
  RealColumn get centerLongitude => real()();
  IntColumn get radiusKilometers => integer()();
  DateTimeColumn get savedAt => dateTime()();
  DateTimeColumn get generatedAt => dateTime()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) = 64)',
    'CHECK (center_latitude BETWEEN -90 AND 90)',
    'CHECK (center_longitude BETWEEN -180 AND 180)',
    'CHECK (radius_kilometers BETWEEN 5 AND 50)',
    'CHECK (length(payload_json) BETWEEN 1 AND 524288)',
  ];
}

/// Deliberately local, user-initiated session watches. This table has no
/// coordinate columns, so following a session cannot become location history.
@DataClassName('WatchedShootingSessionRow')
class WatchedShootingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get snapshotId => text()();
  TextColumn get title => text()();
  TextColumn get kind => text()();
  TextColumn get targetId => text().nullable()();
  DateTimeColumn get watchedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) = 64)',
    'CHECK (length(session_id) BETWEEN 1 AND 160)',
    'CHECK (length(snapshot_id) BETWEEN 1 AND 160)',
    'CHECK (length(title) BETWEEN 1 AND 160)',
    "CHECK (kind IN ('generalMorning', 'generalEvening', 'waterMorning', 'waterEvening', 'mountainMorning', 'mountainEvening', 'cityBlueHour', 'cityAfterRain', 'desertSideLight', 'routeLightWindow'))",
    'CHECK (expires_at >= watched_at)',
  ];
}

@DataClassName('ShootingSessionResultRow')
class ShootingSessionResults extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get snapshotId => text()();
  TextColumn get kind => text()();
  TextColumn get targetId => text().nullable()();
  TextColumn get outcome => text()();
  TextColumn get reasonsJson => text()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) = 64)',
    'CHECK (length(session_id) BETWEEN 1 AND 160)',
    'CHECK (length(snapshot_id) BETWEEN 1 AND 160)',
    "CHECK (kind IN ('generalMorning', 'generalEvening', 'waterMorning', 'waterEvening', 'mountainMorning', 'mountainEvening', 'cityBlueHour', 'cityAfterRain', 'desertSideLight', 'routeLightWindow'))",
    "CHECK (outcome IN ('captured', 'conditionsDidNotAppear', 'arrivedLate', 'didNotGo'))",
    'CHECK (length(reasons_json) BETWEEN 2 AND 512)',
  ];
}

/// A pack is created only after an explicit user action. Its route and place
/// snapshots are immutable JSON, so ordinary environment refreshes cannot add
/// a covert movement trail to it.
@DataClassName('OfflinePhotographyPackRow')
class OfflinePhotographyPacks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dataTimestamp => dateTime()();
  TextColumn get routeJson => text().nullable()();
  TextColumn get placesJson => text()();
  TextColumn get windowsJson => text()();
  TextColumn get sessionJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(id) = 64)',
    'CHECK (length(name) BETWEEN 1 AND 160)',
    'CHECK (data_timestamp <= created_at)',
    'CHECK (route_json IS NULL OR length(route_json) BETWEEN 1 AND 131072)',
    'CHECK (length(places_json) BETWEEN 2 AND 524288)',
    'CHECK (length(windows_json) BETWEEN 2 AND 131072)',
    'CHECK (length(session_json) BETWEEN 2 AND 131072)',
  ];
}

@DriftDatabase(
  tables: [
    SavedPlaces,
    RecentRouteDestinations,
    SavedRoutes,
    SavedJourneys,
    ImportedRouteTracks,
    ProfilePreferenceRecords,
    BaseRegions,
    ManualLocations,
    SavedInspirationNotes,
    WildlifeMapLayerCaches,
    WatchedShootingSessions,
    ShootingSessionResults,
    OfflinePhotographyPacks,
    EntryCacheRecords,
    CompositionCacheRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.production() => AppDatabase(_openConnection());
  factory AppDatabase.inMemory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      // Development baseline: schema 16 is the only supported local shape.
      // Formal data-preserving migrations start when the first RC freezes this
      // schema. Until then, rebuilding avoids carrying ambiguous pre-release
      // models into the runtime or pretending to support partial old schemas.
      for (final table in allTables.toList(growable: false).reversed) {
        await customStatement('DROP TABLE IF EXISTS ${table.actualTableName}');
      }
      await migrator.createAll();
    },
  );

  Future<void> clearDerivedCaches() async {
    await batch((batch) {
      batch.deleteAll(entryCacheRecords);
      batch.deleteAll(compositionCacheRecords);
    });
  }
}

/// Overridden by the Flutter test bootstrap so widget tests never open or
/// mutate the device database. Production keeps the durable factory.
AppDatabase Function() appDatabaseFactory = AppDatabase.production;

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = appDatabaseFactory();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(path.join(directory.path, 'lumanest.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
