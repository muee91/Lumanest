import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_action.dart';
import 'package:luma_nest/src/core/entry/entry_provenance.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/scenario/scenario_context.dart';
import 'package:luma_nest/src/core/scenario/scenario_orchestrator.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';

void main() {
  _selectTodayTests();

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

  test(
    'P0 safety keeps a detail slot without overriding the photography judgement',
    () {
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
      expect(
        composition[CompositionSlot.blockingSafety]!.kind,
        EntryKind.safety,
      );
      expect(
        composition[CompositionSlot.primary]!.kind,
        EntryKind.photographyOpportunity,
      );
      expect(
        composition.judgement,
        composition[CompositionSlot.primary]!.presentation.judgement,
      );
      expect(composition.narrativeFacts, contains('safety_available'));
      expect(composition.narrativeFacts, isNot(contains('safety_override')));
    },
  );

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

void _selectTodayTests() {
  final now = DateTime.utc(2026, 7, 18, 10);

  test('安全条目永远压过更强的拍摄机会，但拍摄判断不被它改写', () {
    final selection = ScenarioOrchestrator.selectToday(
      entries: [
        _entry(id: 'glow', now: now, confidence: .95),
        _entry(
          id: 'storm',
          now: now,
          kind: EntryKind.safety,
          priority: EntryPriority.p0,
          confidence: 0,
        ),
      ],
      now: now,
    );

    expect(selection.blockingSafety?.id, 'storm');
    expect(selection.primary?.id, 'glow');
  });

  test('排序只看规则已经决定的字段：优先级、置信度、起始时间、id', () {
    ContextEntry pick(List<ContextEntry> entries) =>
        ScenarioOrchestrator.selectToday(entries: entries, now: now).primary!;

    expect(
      pick([
        _entry(id: 'lower-priority', now: now, confidence: .99),
        _entry(
          id: 'higher-priority',
          now: now,
          priority: EntryPriority.p1,
          confidence: .05,
        ),
      ]).id,
      'higher-priority',
      reason: 'p1 胜过 p2，即使置信度低得多',
    );
    expect(
      pick([
        _entry(id: 'weak', now: now, confidence: .3),
        _entry(id: 'strong', now: now, confidence: .8),
      ]).id,
      'strong',
    );
    expect(
      pick([
        _entry(id: 'later', now: now, validFromOffset: const Duration(minutes: 5)),
        _entry(id: 'earlier', now: now),
      ]).id,
      'earlier',
    );
    // Identical in every decided field: the tie must break deterministically,
    // not by arrival order, or the hero could change between two refreshes.
    expect(
      pick([
        _entry(id: 'entry-b', now: now),
        _entry(id: 'entry-a', now: now),
      ]).id,
      'entry-a',
    );
  });

  test('过期条目退出，同 dedupeKey 只留更强的那条', () {
    final selection = ScenarioOrchestrator.selectToday(
      entries: [
        _entry(id: 'gone', now: now, expiresIn: const Duration(minutes: -1)),
        _entry(id: 'weak-duplicate', now: now, confidence: .2, dedupeKey: 'x'),
        _entry(id: 'strong-duplicate', now: now, confidence: .7, dedupeKey: 'x'),
      ],
      now: now,
    );

    expect(selection.qualified.map((entry) => entry.id), [
      'strong-duplicate',
    ]);
  });

  test('被压制条目不再与主机会争夺同一视觉层级', () {
    final selection = ScenarioOrchestrator.selectToday(
      entries: [
        _entry(
          id: 'leader',
          now: now,
          priority: EntryPriority.p1,
          suppressionKeys: const {'shadowed'},
        ),
        _entry(id: 'shadowed', now: now),
      ],
      now: now,
    );

    expect(selection.qualified.map((entry) => entry.id), ['leader']);
    expect(selection.primary?.id, 'leader');
  });

  test('没有任何成立条目时不制造主机会', () {
    final selection = ScenarioOrchestrator.selectToday(entries: const [], now: now);

    expect(selection.blockingSafety, isNull);
    expect(selection.primary, isNull);
  });
}

ContextEntry _entry({
  required String id,
  required DateTime now,
  EntryKind kind = EntryKind.photographyOpportunity,
  EntryPriority priority = EntryPriority.p2,
  double confidence = 0.5,
  Duration validFromOffset = Duration.zero,
  Duration expiresIn = const Duration(minutes: 10),
  String? dedupeKey,
  Set<String> suppressionKeys = const {},
}) => ContextEntry(
  id: id,
  kind: kind,
  sourceNamespace: 'test',
  sourceId: id,
  revision: 1,
  observedAt: now,
  validFrom: now.add(validFromOffset),
  expiresAt: now.add(expiresIn),
  freshness: EntryFreshness.fresh,
  evidenceConfidence: confidence,
  basePriority: priority,
  severity: kind == EntryKind.safety
      ? EntrySeverity.warning
      : EntrySeverity.info,
  geoScope: const EntryGeoScope(type: ContextGeoScope.region),
  allowedSurfaces: const {EntrySurface.today},
  actions: const [EntryAction(type: EntryActionType.openExplore)],
  presentation: EntryPresentation(
    variant: kind == EntryKind.safety
        ? EntryPresentationVariant.safety
        : EntryPresentationVariant.manifestOpportunity,
    eyebrow: '测试',
    title: id,
    detail: '详情',
    timeLabel: '现在',
    actionLabel: '查看',
    accent: EntryAccent.sky,
  ),
  dedupeKey: dedupeKey ?? id,
  suppressionKeys: suppressionKeys,
  contentFingerprint: 'sha256:$id',
  payload: const SystemEntryPayload(stateCode: 'test'),
  provenance: [EntryProvenance(sourceId: 'test', observedAt: now)],
);
