import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';

void main() {
  test('quiet city fixture describes an inactive urban context', () {
    final snapshot = ContextFixtures.quietCity();

    expect(snapshot.primaryScene, SceneType.city);
    expect(snapshot.activeRoute, isFalse);
    expect(snapshot.opportunityIds, isEmpty);
  });

  test('lake sunset fixture exposes the current water session', () {
    final snapshot = ContextFixtures.lakeSunset();

    expect(snapshot.primaryScene, SceneType.lake);
    expect(snapshot.dayPhase, DayPhase.sunset);
    expect(snapshot.opportunityIds, contains('session.water.evening'));
  });

  test('mountain dawn fixture exposes the current mountain session', () {
    final snapshot = ContextFixtures.mountainDawn();

    expect(snapshot.primaryScene, SceneType.mountain);
    expect(snapshot.dayPhase, DayPhase.dawn);
    expect(snapshot.opportunityIds, contains('session.mountain.morning'));
  });

  test('snapshot event collections cannot be mutated', () {
    final snapshot = ContextFixtures.lakeSunset();

    expect(
      () => snapshot.opportunityIds.add('fake-opportunity'),
      throwsUnsupportedError,
    );
  });

  group('withWildlifeActivity', () {
    final observedAt = DateTime.utc(2026, 7, 11, 10);
    final expiresAt = observedAt.add(const Duration(minutes: 30));

    /// A snapshot that already carries a structured wildlife-safety event
    /// (bear-risk, sourced from an official notice) plus its safetyEventId
    /// and allowedAction, established before any GBIF regional activity is
    /// applied.
    ContextSnapshot snapshotWithExistingWildlifeSafety() {
      return ContextSnapshot(
        id: 'wildlife-safety-base',
        observedAt: observedAt,
        expiresAt: expiresAt,
        primaryScene: SceneType.mountain,
        dayPhase: DayPhase.day,
        weather: WeatherType.cloudy,
        activeRoute: true,
        safetyEventIds: const ['bear-risk'],
        events: [
          ContextEvent(
            id: 'bear-risk',
            channel: ContextEventChannel.wildlifeSafety,
            source: ContextEventSource.official,
            observedAt: observedAt,
            expiresAt: expiresAt,
            confidence: 0.7,
            geoScope: ContextGeoScope.region,
            safetyLevel: ContextSafetyLevel.warning,
            allowedAction: ContextAction.openSafetyDetail,
          ),
        ],
        allowedActions: const [ContextAction.openSafetyDetail],
      );
    }

    RegionalWildlifeActivity activityWithBear() {
      return RegionalWildlifeActivity(
        radiusKilometers: 5,
        occurrenceSampleSize: 12,
        taxa: [
          const WildlifeTaxon(
            scientificName: 'Ursus arctos',
            group: WildlifeGroup.mammal,
            records: 8,
            commonName: 'Brown Bear',
          ),
        ],
      );
    }

    test('with activity adds only a regional-wildlife wildlifeOpportunity '
        'event (wildlifeHistorical) and no wildlifeSafety or risk events', () {
      final updated = snapshotWithExistingWildlifeSafety().withWildlifeActivity(
        activityWithBear(),
      );

      final updatedEvents = updated.events;
      final updatedIds = updatedEvents.map((event) => event.id).toSet();

      // Only regional-wildlife is newly added as wildlifeOpportunity.
      expect(
        updatedEvents.where(
          (event) => event.channel == ContextEventChannel.wildlifeOpportunity,
        ),
        hasLength(1),
      );
      final wildlifeEvent = updatedEvents.singleWhere(
        (event) => event.channel == ContextEventChannel.wildlifeOpportunity,
      );
      expect(wildlifeEvent.id, 'regional-wildlife');
      expect(wildlifeEvent.source, ContextEventSource.wildlifeHistorical);

      // No new wildlifeSafety channel events are added — only the
      // pre-existing bear-risk must remain.
      expect(
        updatedEvents
            .where(
              (event) => event.channel == ContextEventChannel.wildlifeSafety,
            )
            .map((event) => event.id),
        ['bear-risk'],
      );

      // Explicitly never introduces bear-risk/boar-risk/snake-risk as new
      // wildlifeOpportunity events, in any channel.
      for (final forbiddenId in ['bear-risk', 'boar-risk', 'snake-risk']) {
        expect(
          updatedEvents.where(
            (event) =>
                event.channel == ContextEventChannel.wildlifeOpportunity &&
                event.id == forbiddenId,
          ),
          isEmpty,
          reason: '$forbiddenId must not be added as wildlifeOpportunity',
        );
        expect(
          updatedEvents.where((event) => event.id == forbiddenId).length,
          forbiddenId == 'bear-risk' ? 1 : 0,
          reason:
              '$forbiddenId must not be newly introduced (bear-risk is the '
              'pre-existing wildlifeSafety event and must appear exactly once)',
        );
      }

      // regional-wildlife is the only wildlifeEventId.
      expect(updated.wildlifeEventIds, ['regional-wildlife']);
      expect(updatedIds, containsAll(['regional-wildlife', 'bear-risk']));
    });

    test('with activity preserves pre-existing wildlifeSafety event, '
        'safetyEventIds and allowedActions', () {
      final base = snapshotWithExistingWildlifeSafety();
      final updated = base.withWildlifeActivity(activityWithBear());

      // Pre-existing bear-risk wildlifeSafety event is retained verbatim.
      final bearEvent = updated.events.firstWhere(
        (event) => event.id == 'bear-risk',
        orElse: () => throw StateError('bear-risk event was removed'),
      );
      expect(bearEvent.channel, ContextEventChannel.wildlifeSafety);
      expect(bearEvent.source, ContextEventSource.official);
      expect(bearEvent.safetyLevel, ContextSafetyLevel.warning);
      expect(bearEvent.allowedAction, ContextAction.openSafetyDetail);

      // safetyEventIds preserved.
      expect(updated.safetyEventIds, base.safetyEventIds);
      expect(updated.safetyEventIds, ['bear-risk']);

      // allowedActions preserved.
      expect(updated.allowedActions, base.allowedActions);
      expect(updated.allowedActions, [ContextAction.openSafetyDetail]);
    });

    test('without activity preserves pre-existing wildlifeSafety event, '
        'safetyEventIds and allowedActions and adds no wildlife events', () {
      final base = snapshotWithExistingWildlifeSafety();
      final updated = base.withWildlifeActivity(
        RegionalWildlifeActivity(
          radiusKilometers: 5,
          occurrenceSampleSize: 0,
          taxa: const [],
        ),
      );

      // No wildlifeOpportunity events are produced.
      expect(
        updated.events.where(
          (event) => event.channel == ContextEventChannel.wildlifeOpportunity,
        ),
        isEmpty,
      );
      expect(updated.wildlifeEventIds, isEmpty);

      // No new wildlifeSafety events — only the pre-existing bear-risk.
      expect(
        updated.events
            .where(
              (event) => event.channel == ContextEventChannel.wildlifeSafety,
            )
            .map((event) => event.id),
        ['bear-risk'],
      );
      for (final forbiddenId in ['boar-risk', 'snake-risk']) {
        expect(
          updated.events.where((event) => event.id == forbiddenId),
          isEmpty,
          reason: '$forbiddenId must not be introduced',
        );
      }

      // Pre-existing bear-risk wildlifeSafety event is retained.
      final bearEvent = updated.events.firstWhere(
        (event) => event.id == 'bear-risk',
        orElse: () => throw StateError('bear-risk event was removed'),
      );
      expect(bearEvent.channel, ContextEventChannel.wildlifeSafety);
      expect(bearEvent.source, ContextEventSource.official);

      // safetyEventIds and allowedActions preserved.
      expect(updated.safetyEventIds, base.safetyEventIds);
      expect(updated.allowedActions, base.allowedActions);
    });
  });
}
