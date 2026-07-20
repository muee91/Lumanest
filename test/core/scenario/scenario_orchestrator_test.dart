import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/scenario/scenario_context.dart';
import 'package:luma_nest/src/core/scenario/scenario_orchestrator.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';

void main() {
  test('Today composition promotes the session without page arbitration', () {
    final now = DateTime.now().toUtc();
    final snapshot = ContextFixtures.lakeSunset(observedAt: now);
    final composition = _compose(snapshot);

    final primary = composition[CompositionSlot.primary]!;
    expect(primary.kind, EntryKind.photographyOpportunity);
    expect(
      primary.presentation.variant,
      EntryPresentationVariant.shootingSession,
    );
    expect((primary.payload as OpportunityEntryPayload).sessionId, isNotNull);
    expect(composition[CompositionSlot.blockingSafety], isNull);
  });

  test('P0 safety occupies the blocking slot over a shooting session', () {
    final now = DateTime.now().toUtc();
    final base = ContextFixtures.lakeSunset(observedAt: now);
    final storm = ContextEvent(
      id: 'thunderstorm',
      channel: ContextEventChannel.safety,
      source: ContextEventSource.weather,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      confidence: .95,
      safetyLevel: ContextSafetyLevel.warning,
      allowedAction: ContextAction.openSafetyDetail,
    );
    final snapshot = ContextSnapshot(
      id: base.id,
      observedAt: now,
      expiresAt: base.expiresAt,
      primaryScene: base.primaryScene,
      dayPhase: base.dayPhase,
      weather: base.weather,
      activeRoute: base.activeRoute,
      location: base.location,
      windSpeedMetersPerSecond: base.windSpeedMetersPerSecond,
      visibilityKilometers: base.visibilityKilometers,
      precipitationMillimeters: base.precipitationMillimeters,
      cloudCoverPercent: base.cloudCoverPercent,
      opportunityIds: base.opportunityIds,
      safetyEventIds: const ['thunderstorm'],
      events: [...base.events, storm],
      shootingSessions: base.shootingSessions,
      allowedActions: const [ContextAction.openSafetyDetail],
    );
    final composition = _compose(snapshot);

    expect(composition[CompositionSlot.blockingSafety], isNotNull);
    expect(composition[CompositionSlot.blockingSafety]!.kind, EntryKind.safety);
    expect(
      composition[CompositionSlot.primary]!.kind,
      EntryKind.photographyOpportunity,
    );
    expect(composition.judgement, '先把风险放在所有创作之前。');
  });

  test('an explicit empty canonical entry list stays quiet', () {
    final now = DateTime.now().toUtc();
    final base = ContextFixtures.lakeSunset(observedAt: now);
    final snapshot = ContextSnapshot(
      id: base.id,
      observedAt: now,
      expiresAt: base.expiresAt,
      primaryScene: base.primaryScene,
      dayPhase: base.dayPhase,
      weather: base.weather,
      activeRoute: base.activeRoute,
      location: base.location,
      opportunityIds: base.opportunityIds,
      events: base.events,
      shootingSessions: base.shootingSessions,
      canonicalEntriesPresent: true,
    );
    final composition = _compose(snapshot);

    expect(composition[CompositionSlot.blockingSafety], isNull);
    expect(
      composition[CompositionSlot.primary]!.presentation.variant,
      EntryPresentationVariant.quiet,
    );
  });
}

SurfaceComposition _compose(ContextSnapshot snapshot) {
  final manifest = ManifestPolicy.build(snapshot, now: snapshot.observedAt);
  return const ScenarioOrchestrator().composeToday(
    ScenarioContext(
      surface: EntrySurface.today,
      now: snapshot.observedAt,
      snapshot: snapshot,
      manifest: manifest,
      narrative: null,
      skyOpportunity: null,
      nextWindow: null,
      nextSunrise: null,
    ),
  );
}
