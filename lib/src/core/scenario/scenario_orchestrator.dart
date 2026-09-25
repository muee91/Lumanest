import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_adapter.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/core/scenario/scenario_context.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';

class ScenarioOrchestrator {
  const ScenarioOrchestrator();

  SurfaceComposition composeToday(ScenarioContext context) {
    final now = context.now.toUtc();
    final entries = <ContextEntry>[];
    final eventById = {
      for (final event in context.snapshot.events) event.id: event,
    };
    final hasCanonicalEntries = context.snapshot.canonicalEntriesPresent;

    final safetyEntries = <ContextEntry>[];
    if (hasCanonicalEntries) {
      safetyEntries.addAll(
        context.snapshot.entries.where(
          (entry) =>
              entry.kind == EntryKind.safety &&
              entry.allowedSurfaces.contains(EntrySurface.today) &&
              !entry.isExpiredAt(now),
        ),
      );
    } else {
      for (final event in context.snapshot.events) {
        if ((event.channel == ContextEventChannel.safety ||
                event.channel == ContextEventChannel.wildlifeSafety) &&
            !event.isExpiredAt(now)) {
          final item = context.manifest.safety
              .where((candidate) => candidate.id == event.id)
              .firstOrNull;
          if (item != null) {
            safetyEntries.add(
              ContextEntryAdapter.fromManifestItem(
                item,
                summary: context.manifest.summary,
                observedAt: event.observedAt,
                expiresAt: event.expiresAt,
              ),
            );
          }
        }
      }
    }
    safetyEntries.sort(_compareEntries);
    entries.addAll(safetyEntries);

    if (!context.snapshot.isStale) {
      final canonicalSessionIds = hasCanonicalEntries
          ? context.snapshot.entries
                .where(
                  (entry) =>
                      entry.allowedSurfaces.contains(EntrySurface.today) &&
                      entry.payload is OpportunityEntryPayload,
                )
                .map(
                  (entry) =>
                      (entry.payload as OpportunityEntryPayload).sessionId,
                )
                .whereType<String>()
                .toSet()
          : null;
      final session = ShootingSessionSelector.select(
        context.snapshot.shootingSessions.where(
          (item) =>
              canonicalSessionIds == null ||
              canonicalSessionIds.contains(item.id),
        ),
        now: now,
      );
      if (session != null && !session.isEvidenceExpiredAt(now)) {
        entries.add(
          ContextEntryAdapter.fromShootingSession(
            session,
            observedAt: context.snapshot.observedAt,
          ),
        );
      }
      if (hasCanonicalEntries) {
        entries.addAll(
          context.snapshot.entries.where(
            (entry) =>
                entry.kind != EntryKind.safety &&
                entry.allowedSurfaces.contains(EntrySurface.today) &&
                !entry.isExpiredAt(now) &&
                (entry.payload is! OpportunityEntryPayload ||
                    (entry.payload as OpportunityEntryPayload).sessionId ==
                        null),
          ),
        );
      }
      final forecast = context.skyOpportunity;
      if (forecast != null && forecast.isProactivelyVisibleAt(now)) {
        entries.add(
          ContextEntryAdapter.fromSkyOpportunity(
            forecast,
            observedAt: context.snapshot.observedAt,
          ),
        );
      }
      final nextWindow = context.nextWindow;
      if (session == null && nextWindow != null) {
        entries.add(
          ContextEntryAdapter.fromNextWindow(
            nextWindow,
            observedAt: context.snapshot.observedAt,
          ),
        );
      }
    }

    final manifestItems = <ManifestItem>[
      if (!hasCanonicalEntries && context.manifest.primary != null)
        context.manifest.primary!,
      if (!hasCanonicalEntries) ...context.manifest.secondary,
    ];
    for (final item in manifestItems) {
      if (eventById[item.id]?.channel == ContextEventChannel.safety ||
          item.action == ManifestAction.openShootingWindow) {
        continue;
      }
      entries.add(
        ContextEntryAdapter.fromManifestItem(
          item,
          summary: context.narrative?.summary.trim().isNotEmpty == true
              ? context.narrative!.summary
              : context.manifest.summary,
          observedAt: context.snapshot.observedAt,
          expiresAt: context.snapshot.expiresAt,
        ),
      );
    }

    final selection = selectToday(entries: entries, now: now);
    final blockingSafety = selection.blockingSafety;
    final primary = selection.primary;
    final quiet = primary == null;
    final selectedPrimary =
        primary ??
        ContextEntryAdapter.quiet(
          snapshot: context.snapshot,
          now: now,
          nextSunrise: context.nextSunrise,
          detail: context.narrative?.summary.trim().isNotEmpty == true
              ? context.narrative!.summary
              : '我会继续看风、云与光线的变化',
        );
    final slots = <CompositionSlot, ContextEntry>{
      CompositionSlot.blockingSafety: ?blockingSafety,
      CompositionSlot.primary: selectedPrimary,
    };
    final judgement = _judgement(
      primary: selectedPrimary,
      narrative: context.narrative?.summary,
    );
    return SurfaceComposition(
      id: 'composition_today_${context.snapshot.id}',
      surface: EntrySurface.today,
      revision: context.snapshot.observedAt.toUtc().microsecondsSinceEpoch,
      generatedAt: now,
      slots: slots,
      judgement: judgement,
      narrativeFacts: {
        if (quiet) 'quiet',
        if (blockingSafety != null) 'safety_available',
        selectedPrimary.sourceId,
      },
    );
  }

  /// Composes the Explore surface from the same canonical Entry stream used by
  /// Today. Map rendering may continue to use NearbyPlace domain objects, but
  /// recommendation order, conflict handling and capacity are decided here.
  SurfaceComposition composeExplore({
    required Iterable<ContextEntry> entries,
    required DateTime now,
    required int revision,
    String id = 'composition_explore',
  }) {
    final moment = now.toUtc();
    final qualified = _qualify(
      entries
          .where(
            (entry) =>
                entry.allowedSurfaces.contains(EntrySurface.explore) &&
                !entry.isExpiredAt(moment),
          )
          .toList(growable: false),
      moment,
    );
    final safety = qualified
        .where((entry) => entry.kind == EntryKind.safety)
        .firstOrNull;
    final creative = qualified
        .where((entry) => entry.kind != EntryKind.safety)
        .toList(growable: false);
    final places = creative
        .where((entry) => entry.kind == EntryKind.place)
        .toList(growable: false);
    final primary = creative.firstOrNull;
    final slots = <CompositionSlot, ContextEntry>{
      CompositionSlot.blockingSafety: ?safety,
      CompositionSlot.primary: ?primary,
      CompositionSlot.mapHighlight: ?places.firstOrNull,
      CompositionSlot.secondaryA: ?creative.skip(1).firstOrNull,
      CompositionSlot.secondaryB: ?creative.skip(2).firstOrNull,
    };
    final judgement = safety != null
        ? '先确认风险，再决定往哪里探索。'
        : primary?.presentation.judgement ??
              primary?.presentation.title ??
              '附近暂时没有达到展示条件的发现。';
    return SurfaceComposition(
      id: id,
      surface: EntrySurface.explore,
      revision: revision,
      generatedAt: moment,
      slots: slots,
      judgement: judgement,
      narrativeFacts: {
        if (safety != null) 'safety_override',
        if (primary == null) 'quiet',
        ...slots.values.map((entry) => entry.sourceId),
      },
    );
  }

  /// The single authority for what leads Today.
  ///
  /// Safety leads whenever one is present and unexpired; otherwise the strongest
  /// remaining entry leads. Ranking reads only fields the rule engine already
  /// decided — base priority, evidence confidence, validity window — so there is
  /// no second ordering anywhere that could contradict this one, and
  /// docs/core-1.0-scope.md's one-main-opportunity rule has exactly one home.
  static TodaySelection selectToday({
    required List<ContextEntry> entries,
    required DateTime now,
  }) {
    final qualified = _qualify(entries, now);
    return TodaySelection._(
      qualified: qualified,
      blockingSafety: qualified
          .where((entry) => entry.kind == EntryKind.safety)
          .firstOrNull,
      primary: qualified
          .where((entry) => entry.kind != EntryKind.safety)
          .firstOrNull,
    );
  }

  /// Produces a deterministic qualified list in display order.
  static List<ContextEntry> _qualify(List<ContextEntry> entries, DateTime now) {
    final deduped = _dedupe(entries, now);
    final selected = <ContextEntry>[];
    final activeSuppressionKeys = <String>{};

    for (final entry in deduped) {
      if (_entryKeys(entry).any(activeSuppressionKeys.contains)) continue;
      selected.add(entry);
      activeSuppressionKeys.addAll(entry.suppressionKeys);
    }

    return List.unmodifiable(selected);
  }

  static Set<String> _entryKeys(ContextEntry entry) => {
    entry.id,
    entry.sourceId,
    entry.dedupeKey,
    'kind:${entry.kind.name}',
    ...entry.suppressionKeys.map((key) => 'alias:$key'),
  };

  static List<ContextEntry> _dedupe(List<ContextEntry> entries, DateTime now) {
    final byKey = <String, ContextEntry>{};
    for (final entry in entries) {
      if (!entry.expiresAt.isAfter(now)) continue;
      final existing = byKey[entry.dedupeKey];
      if (existing == null || _compareEntries(entry, existing) < 0) {
        byKey[entry.dedupeKey] = entry;
      }
    }
    final result = byKey.values.toList(growable: false)..sort(_compareEntries);
    return result;
  }

  static int _compareEntries(ContextEntry left, ContextEntry right) {
    final priority = _priority(
      right.basePriority,
    ).compareTo(_priority(left.basePriority));
    if (priority != 0) return priority;
    final confidence = right.evidenceConfidence.compareTo(
      left.evidenceConfidence,
    );
    if (confidence != 0) return confidence;
    final time = left.validFrom.compareTo(right.validFrom);
    if (time != 0) return time;
    return left.id.compareTo(right.id);
  }

  static int _priority(EntryPriority value) => switch (value) {
    EntryPriority.p0 => 1000,
    EntryPriority.p1 => 700,
    EntryPriority.p2 => 400,
    EntryPriority.p3 => 100,
  };

  static String _judgement({
    required ContextEntry primary,
    required String? narrative,
  }) {
    final text = narrative?.trim() ?? '';
    if (text.isNotEmpty &&
        primary.presentation.variant ==
            EntryPresentationVariant.manifestOpportunity) {
      return text;
    }
    return primary.presentation.judgement ?? primary.presentation.title;
  }
}

/// What [ScenarioOrchestrator.selectToday] decided, kept separate from the
/// surface that consumes it so the choice can be tested without a widget tree.
class TodaySelection {
  const TodaySelection._({
    required this.qualified,
    required this.blockingSafety,
    required this.primary,
  });

  /// Display-ordered entries that survived expiry, dedupe and suppression.
  final List<ContextEntry> qualified;

  /// The safety entry that outranks everything, or `null`.
  final ContextEntry? blockingSafety;

  /// The one main photography opportunity, or `null` when Today stays quiet.
  final ContextEntry? primary;
}
