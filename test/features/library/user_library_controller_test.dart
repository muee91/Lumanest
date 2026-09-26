import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
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

  test('clears only the selected local library category', () async {
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

    final session = ContextFixtures.waterEveningSession(
      observedAt: DateTime.now(),
    );
    await controller.watchSession(session: session, snapshotId: 'snapshot-1');
    await controller.recordShootingSessionResult(
      session: session,
      snapshotId: 'snapshot-1',
      outcome: ShootingSessionOutcome.captured,
    );

    await controller.clearRecentRoute();
    expect(store.value.recentRoute, isNull);
    expect(store.value.savedRoutes, hasLength(1));
    expect(store.value.watchedSessions, hasLength(1));
    expect(store.value.sessionResults, hasLength(1));

    await controller.clearSavedRoutes();
    expect(store.value.savedRoutes, isEmpty);
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

  test('keeps explicit shooting records local and clearable', () async {
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

    expect(store.value.watchedSessions.single.sessionId, session.id);
    expect(
      store.value.sessionResults.single.outcome,
      ShootingSessionOutcome.arrivedLate,
    );
    expect(store.value.toExportJson()['format'], 'lumanest-local-library-v4');

    await controller.clearPhotographyActivity();

    expect(store.value.watchedSessions, isEmpty);
    expect(store.value.sessionResults, isEmpty);
  });
}

class _FakeStore implements UserLibraryStore {
  _FakeStore(this.value);
  UserLibraryState value;

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}
