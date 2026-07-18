import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

void main() {
  test('saved authority notes reject non-HTTPS action targets', () {
    final saved = SavedInspirationNote.fromNote(
      snapshotId: 'unsafe',
      note: InspirationNote(
        id: 'astronomy-catalog:unsafe',
        label: '看天象',
        emoji: '✨',
        category: InspirationCategory.light,
        kind: InspirationNoteKind.factualOpportunity,
        action: ManifestAction.openAstronomyDetail,
        detail: '不应打开非 HTTPS 地址。',
        priority: 100,
        ttl: const Duration(minutes: 30),
        authorityUri: Uri.parse('http://example.com/event'),
      ),
      savedAt: DateTime.utc(2026, 7, 15),
    );

    expect(saved.authorityUri, isNull);
    expect(saved.manifestItem, isNull);
  });

  test('restores, toggles and persists saved places', () async {
    final store = _FakeStore(
      const UserLibraryState(
        savedPlaces: [
          SavedPlace(
            id: 'a',
            name: '湖岸机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final restored = await container.read(userLibraryProvider.future);
    expect(restored.savedPlaces.single.id, 'a');

    await container
        .read(userLibraryProvider.notifier)
        .togglePlace(
          const SavedPlace(
            id: 'b',
            name: '古镇',
            category: 'humanity',
            latitude: 31,
            longitude: 121,
          ),
        );
    expect(
      store.value.savedPlaces.map((place) => place.id),
      containsAll(['a', 'b']),
    );

    await container
        .read(userLibraryProvider.notifier)
        .togglePlace(store.value.savedPlaces.first);
    expect(
      store.value.savedPlaces.map((place) => place.id),
      isNot(contains('a')),
    );
  });

  test('persists only the latest route destination', () async {
    final store = _FakeStore(const UserLibraryState());
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(userLibraryProvider.future);

    await container
        .read(userLibraryProvider.notifier)
        .saveRecentRoute(
          const SavedRouteDestination(
            name: '雪山机位',
            latitude: 30,
            longitude: 101,
            travelMode: 'walking',
          ),
        );

    expect(store.value.recentRoute?.name, '雪山机位');
    expect(store.value.recentRoute?.travelMode, 'walking');
  });

  test('explicitly saves and removes a bounded local route', () async {
    final store = _FakeStore(const UserLibraryState());
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(userLibraryProvider.future);
    const destination = SavedRouteDestination(
      name: '雪山机位',
      latitude: 30,
      longitude: 101,
      travelMode: 'walking',
    );
    final controller = container.read(userLibraryProvider.notifier);

    await controller.toggleSavedRoute(destination);

    expect(store.value.savedRoutes, hasLength(1));
    expect(store.value.savedRoutes.single.destination.name, '雪山机位');
    expect(store.value.savedRoutes.single.id, hasLength(64));
    expect(store.value.recentRoute, isNull);

    await controller.toggleSavedRoute(destination);
    expect(store.value.savedRoutes, isEmpty);
  });

  test('records an explicit journey lifecycle and rejects overlap', () async {
    final store = _FakeStore(const UserLibraryState());
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(userLibraryProvider.future);
    const first = SavedRouteDestination(
      name: '湖岸行程',
      latitude: 30,
      longitude: 120,
    );
    const second = SavedRouteDestination(
      name: '山地行程',
      latitude: 31,
      longitude: 121,
      travelMode: 'walking',
    );
    final controller = container.read(userLibraryProvider.notifier);

    final started = await controller.startJourney(first);
    expect(started.isActive, isTrue);
    expect(store.value.activeJourney?.destination.name, '湖岸行程');
    expect(await controller.startJourney(first), same(started));
    await expectLater(
      controller.startJourney(second),
      throwsA(isA<ActiveJourneyConflict>()),
    );

    await controller.endJourney(first);
    expect(store.value.activeJourney, isNull);
    expect(store.value.journeys.single.endedAt, isNotNull);
  });

  test('cold-start restorer activates an unfinished walking journey', () async {
    final store = _FakeStore(
      UserLibraryState(
        journeys: [
          SavedJourney.start(
            const SavedRouteDestination(
              name: '山谷步道',
              latitude: 30,
              longitude: 120,
              travelMode: 'walking',
            ),
            startedAt: DateTime.utc(2026, 7, 15, 8),
            routeKey: 'track-1',
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(journeyRouteContextRestorerProvider).restore();

    expect(
      container.read(routeContextStateProvider),
      RouteContextState.active(ContextRouteMode.hiking),
    );
  });

  test('persists and deletes an imported GPX track', () async {
    final store = _FakeStore(const UserLibraryState());
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    const points = [
      GeoPoint(latitude: 30, longitude: 120),
      GeoPoint(latitude: 30.1, longitude: 120.1),
    ];
    final track = ImportedRouteTrack(
      id: 'track-1',
      name: '导入徒步',
      importedAt: DateTime.utc(2026, 7, 15),
      points: points,
      distanceMeters: 1000,
      durationSeconds: 600,
      durationEstimated: false,
    );

    await container.read(userLibraryProvider.notifier).saveImportedTrack(track);
    expect(store.value.importedTracks.single.id, 'track-1');

    await container
        .read(userLibraryProvider.notifier)
        .deleteImportedTrack('track-1');
    expect(store.value.importedTracks, isEmpty);
  });

  test('keeps an imported track while its journey is active', () async {
    final track = ImportedRouteTrack(
      id: 'active-track',
      name: '进行中徒步',
      importedAt: DateTime.utc(2026, 7, 15),
      points: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.1, longitude: 120.1),
      ],
      distanceMeters: 1000,
      durationSeconds: 600,
      durationEstimated: false,
    );
    final destination = SavedRouteDestination(
      name: track.name,
      latitude: track.destination.latitude,
      longitude: track.destination.longitude,
      travelMode: 'walking',
    );
    final store = _FakeStore(
      UserLibraryState(
        importedTracks: [track],
        journeys: [
          SavedJourney.start(
            destination,
            startedAt: DateTime.utc(2026, 7, 15, 8),
            routeKey: track.id,
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(userLibraryProvider.notifier);

    await expectLater(
      controller.deleteImportedTrack(track.id),
      throwsA(isA<ActiveImportedTrackConflict>()),
    );
    await expectLater(
      controller.clearImportedTracks(),
      throwsA(isA<ActiveImportedTrackConflict>()),
    );
    expect(store.value.importedTracks.single.id, track.id);
  });

  test('clears only the selected local library category', () async {
    final track = ImportedRouteTrack(
      id: 'track-1',
      name: '导入徒步',
      importedAt: DateTime.utc(2026, 7, 15),
      points: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.1, longitude: 120.1),
      ],
      distanceMeters: 1000,
      durationSeconds: 600,
      durationEstimated: false,
    );
    final store = _FakeStore(
      UserLibraryState(
        savedPlaces: const [
          SavedPlace(
            id: 'place-1',
            name: '湖岸机位',
            category: 'viewpoint',
            latitude: 30,
            longitude: 120,
          ),
        ],
        recentRoute: const SavedRouteDestination(
          name: '山路',
          latitude: 31,
          longitude: 121,
        ),
        savedRoutes: [
          SavedRoute.fromDestination(
            const SavedRouteDestination(
              name: '主动保存路线',
              latitude: 30.5,
              longitude: 120.5,
            ),
            savedAt: DateTime.utc(2026, 7, 15),
          ),
        ],
        journeys: [
          SavedJourney.start(
            const SavedRouteDestination(
              name: '进行中行程',
              latitude: 30.6,
              longitude: 120.6,
            ),
            startedAt: DateTime.utc(2026, 7, 15),
          ),
        ],
        importedTracks: [track],
      ),
    );
    final container = ProviderContainer(
      overrides: [userLibraryStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(userLibraryProvider.future);
    final controller = container.read(userLibraryProvider.notifier);

    await controller.clearSavedPlaces();
    expect(store.value.savedPlaces, isEmpty);
    expect(store.value.recentRoute, isNotNull);
    expect(store.value.savedRoutes, hasLength(1));
    expect(store.value.journeys, hasLength(1));
    expect(store.value.importedTracks, hasLength(1));

    final session = ContextFixtures.waterEveningSession(
      observedAt: DateTime.now(),
    );
    await controller.watchSession(session: session, snapshotId: 'snapshot-1');
    await controller.recordShootingSessionResult(
      session: session,
      snapshotId: 'snapshot-1',
      outcome: ShootingSessionOutcome.captured,
    );
    await controller.saveOfflinePhotographyPack(
      OfflinePhotographyPack.create(
        name: '本地拍摄包',
        createdAt: DateTime.now(),
        dataTimestamp: DateTime.now().subtract(const Duration(minutes: 1)),
        places: const [],
        windows: const [],
        sessionSnapshot: const {'sessions': []},
      ),
    );

    await controller.clearRecentRoute();
    expect(store.value.recentRoute, isNull);
    expect(store.value.savedRoutes, hasLength(1));
    expect(store.value.journeys, hasLength(1));
    expect(store.value.watchedSessions, hasLength(1));
    expect(store.value.sessionResults, hasLength(1));
    expect(store.value.offlinePhotographyPacks, hasLength(1));

    await controller.clearSavedRoutes();
    expect(store.value.savedRoutes, isEmpty);
    expect(store.value.journeys, hasLength(1));

    await controller.clearJourneys();
    expect(store.value.journeys, isEmpty);
    expect(store.value.importedTracks, hasLength(1));

    await controller.clearImportedTracks();
    expect(store.value.importedTracks, isEmpty);
  });

  test(
    'saves and removes a local inspiration note without source context',
    () async {
      final store = _FakeStore(const UserLibraryState());
      final container = ProviderContainer(
        overrides: [userLibraryStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(userLibraryProvider.future);
      const note = InspirationNote(
        id: 'session.water.evening',
        label: '找倒影',
        emoji: '🪞',
        category: InspirationCategory.place,
        kind: InspirationNoteKind.factualOpportunity,
        action: ManifestAction.openExplore,
        detail: '风正在变小，去湖岸找一段干净的水面。',
        priority: 100,
        ttl: Duration(minutes: 30),
      );
      final controller = container.read(userLibraryProvider.notifier);

      await controller.saveInspirationNote(snapshotId: 'context-1', note: note);
      await controller.saveInspirationNote(snapshotId: 'context-1', note: note);

      expect(store.value.savedNotes, hasLength(1));
      expect(store.value.savedNotes.single.displayLabel, '找倒影🪞');
      expect(
        store.value.savedNotes.single.sourceNoteId,
        'session.water.evening',
      );
      expect(
        store.value.savedNotes.single.action,
        ManifestAction.openExplore.name,
      );
      expect(store.value.savedNotes.single.id, hasLength(64));

      await controller.deleteSavedNote(store.value.savedNotes.single.id);
      expect(store.value.savedNotes, isEmpty);
    },
  );

  test(
    'keeps explicit photography feedback and packs local and clearable',
    () async {
      final store = _FakeStore(const UserLibraryState());
      final container = ProviderContainer(
        overrides: [userLibraryStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(userLibraryProvider.future);
      final controller = container.read(userLibraryProvider.notifier);

      final session = ContextFixtures.waterEveningSession(
        observedAt: DateTime.now(),
      );
      await controller.watchSession(session: session, snapshotId: 'snapshot-2');
      await controller.recordShootingSessionResult(
        session: session,
        snapshotId: 'snapshot-2',
        outcome: ShootingSessionOutcome.arrivedLate,
        reasons: const {ShootingSessionOutcomeReason.target},
      );
      await controller.saveOfflinePhotographyPack(
        OfflinePhotographyPack.create(
          name: '山谷清晨',
          createdAt: DateTime.utc(2026, 7, 15, 8),
          dataTimestamp: DateTime.utc(2026, 7, 15, 7, 50),
          places: const [],
          windows: [
            OfflinePhotographyWindow(
              id: 'mist',
              label: '晨雾',
              startsAt: DateTime.utc(2026, 7, 16, 5),
              endsAt: DateTime.utc(2026, 7, 16, 6),
            ),
          ],
          sessionSnapshot: const {'sessions': []},
        ),
      );

      expect(store.value.watchedSessions.single.sessionId, session.id);
      expect(
        store.value.sessionResults.single.outcome,
        ShootingSessionOutcome.arrivedLate,
      );
      expect(store.value.offlinePhotographyPacks.single.name, '山谷清晨');
      expect(store.value.toExportJson()['format'], 'lumanest-local-library-v4');

      await controller.clearPhotographyActivity();

      expect(store.value.watchedSessions, isEmpty);
      expect(store.value.sessionResults, isEmpty);
      expect(store.value.offlinePhotographyPacks, isEmpty);
    },
  );
}

class _FakeStore implements UserLibraryStore {
  _FakeStore(this.value);
  UserLibraryState value;

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}
