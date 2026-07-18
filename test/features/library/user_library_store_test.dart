import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

void main() {
  late AppDatabase database;
  late DriftUserLibraryStore store;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftUserLibraryStore(database);
  });

  tearDown(() => database.close());

  test('drift store round-trips the current library schema', () async {
    final observedAt = DateTime.utc(2026, 7, 15, 17);
    final session = ContextFixtures.waterEveningSession(observedAt: observedAt);
    final state = UserLibraryState(
      savedPlaces: const [
        SavedPlace(
          id: 'place-1',
          name: '机位',
          category: 'viewpoint',
          latitude: 30,
          longitude: 120,
        ),
      ],
      recentRoute: const SavedRouteDestination(
        name: '终点',
        latitude: 31,
        longitude: 121,
        travelMode: 'walking',
      ),
      savedRoutes: [
        SavedRoute.fromDestination(
          const SavedRouteDestination(
            name: '湖岸收藏路线',
            latitude: 30.2,
            longitude: 120.1,
          ),
          savedAt: DateTime.utc(2026, 7, 15, 8),
        ),
      ],
      journeys: [
        SavedJourney.start(
          const SavedRouteDestination(
            name: '清晨徒步',
            latitude: 30.3,
            longitude: 120.2,
            travelMode: 'walking',
          ),
          startedAt: DateTime.utc(2026, 7, 15, 6),
          routeKey: 'track-1',
        ).end(DateTime.utc(2026, 7, 15, 8)),
      ],
      importedTracks: [
        ImportedRouteTrack(
          id: 'track-1',
          name: '本地徒步',
          importedAt: DateTime.utc(2026, 7, 15),
          points: const [
            GeoPoint(latitude: 30, longitude: 120),
            GeoPoint(latitude: 30.1, longitude: 120.1),
          ],
          segmentBreakIndexes: const [],
          distanceMeters: 1200,
          durationSeconds: 900,
          durationEstimated: false,
          ascentMeters: 80,
          descentMeters: 20,
        ),
      ],
      savedNotes: [
        SavedInspirationNote.fromNote(
          snapshotId: 'snapshot-1',
          note: InspirationNote(
            id: 'astronomy-catalog:event-1',
            label: '看天象',
            emoji: '✨',
            category: InspirationCategory.light,
            kind: InspirationNoteKind.factualOpportunity,
            action: ManifestAction.openAstronomyDetail,
            detail: '查看经过审核的权威天象目录。',
            priority: 100,
            ttl: const Duration(minutes: 30),
            authorityUri: Uri.parse('https://science.nasa.gov/event-1'),
          ),
          savedAt: observedAt,
        ),
      ],
      watchedSessions: [
        WatchedShootingSession.create(
          session: session,
          snapshotId: 'snapshot-1',
          watchedAt: observedAt,
        ),
      ],
      sessionResults: [
        ShootingSessionResult.record(
          session: session,
          snapshotId: 'snapshot-1',
          outcome: ShootingSessionOutcome.captured,
          recordedAt: observedAt.add(const Duration(hours: 2)),
          reasons: const {ShootingSessionOutcomeReason.cloud},
        ),
      ],
      offlinePhotographyPacks: [
        OfflinePhotographyPack.create(
          name: '湖岸晚霞',
          createdAt: DateTime.utc(2026, 7, 15, 12),
          dataTimestamp: DateTime.utc(2026, 7, 15, 11, 50),
          places: const [],
          windows: const [],
          sessionSnapshot: const {
            'format': 'lumanest-route-photography-v2',
            'sessions': [],
          },
        ),
      ],
    );

    await store.write(state);
    final restored = await store.read();

    expect(restored.savedPlaces.single.name, '机位');
    expect(restored.recentRoute?.travelMode, 'walking');
    expect(restored.savedRoutes.single.destination.name, '湖岸收藏路线');
    expect(restored.journeys.single.routeKey, 'track-1');
    expect(restored.importedTracks.single.ascentMeters, 80);
    expect(restored.savedNotes.single.displayLabel, '看天象✨');
    expect(restored.watchedSessions.single.sessionId, session.id);
    expect(
      restored.watchedSessions.single.kind,
      ShootingSessionKind.waterEvening,
    );
    expect(
      restored.sessionResults.single.outcome,
      ShootingSessionOutcome.captured,
    );
    expect(restored.sessionResults.single.reasons, {
      ShootingSessionOutcomeReason.cloud,
    });
    expect(
      restored.offlinePhotographyPacks.single.sessionSnapshot['sessions'],
      isEmpty,
    );
    expect(restored.toExportJson()['format'], 'lumanest-local-library-v4');
  });

  test('a write replaces removed current-schema values', () async {
    await store.write(
      const UserLibraryState(
        savedPlaces: [
          SavedPlace(
            id: 'old',
            name: '旧机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        ],
      ),
    );

    await store.write(const UserLibraryState());
    final restored = await store.read();

    expect(restored.savedPlaces, isEmpty);
    expect(restored.watchedSessions, isEmpty);
    expect(restored.sessionResults, isEmpty);
  });
}
