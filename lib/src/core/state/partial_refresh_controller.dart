import 'dart:async';

import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';
import 'package:luma_nest/src/core/state/context_delta.dart';
import 'package:luma_nest/src/core/state/environment_state.dart';
import 'package:luma_nest/src/core/state/state_slice.dart';

class EnvironmentSliceBatch {
  const EnvironmentSliceBatch({
    required this.transactionId,
    required this.reason,
    required this.slices,
    required this.entries,
    this.compositions = const {},
  });

  final String transactionId;
  final String reason;
  final Map<EnvironmentSliceKey, StateSlice<Object?>> slices;
  final EntryBatch entries;
  final Map<EntrySurface, SurfaceComposition> compositions;
}

class PartialRefreshController {
  PartialRefreshController({required this._entryStore});

  final ContextEntryStore _entryStore;
  final StreamController<ContextDelta> _changes =
      StreamController<ContextDelta>.broadcast(sync: true);
  EnvironmentState? _state;
  Map<EntrySurface, SurfaceComposition> _compositions = const {};

  EnvironmentState? get state => _state;
  Map<EntrySurface, SurfaceComposition> get compositions => _compositions;

  Stream<ContextDelta> watch() => _changes.stream;

  ContextDelta apply(EnvironmentSliceBatch batch) {
    final previous = _state;
    final previousRevision = previous?.revision ?? 0;
    final entryDelta = _entryStore.apply(batch.entries);
    final changedSlices = <EnvironmentSliceKey>{};
    final nextSlices = <EnvironmentSliceKey, StateSlice<Object?>>{
      ...?previous?.slices,
    };
    for (final entry in batch.slices.entries) {
      final old = nextSlices[entry.key];
      if (old == null ||
          old.revision != entry.value.revision ||
          old.sourceFingerprint != entry.value.sourceFingerprint) {
        changedSlices.add(entry.key);
      }
      nextSlices[entry.key] = entry.value;
    }

    final compositionDiffs = <EntrySurface, CompositionDiff>{};
    if (batch.compositions.isNotEmpty) {
      for (final next in batch.compositions.entries) {
        final diff = _diffComposition(
          _compositions[next.key],
          next.value,
          changedSlices,
        );
        if (_hasCompositionChanges(diff)) {
          compositionDiffs[next.key] = diff;
        }
      }
      for (final previousSurface in _compositions.keys) {
        if (batch.compositions.containsKey(previousSurface)) continue;
        final previousComposition = _compositions[previousSurface]!;
        compositionDiffs[previousSurface] = CompositionDiff(
          removed: previousComposition.slots.keys.toSet(),
          ambientChanged: changedSlices.contains(EnvironmentSliceKey.ambient),
          narrativeFactsChanged: previousComposition.narrativeFacts.isNotEmpty,
        );
      }
      _compositions = Map.unmodifiable(batch.compositions);
    }

    final hasChanges =
        changedSlices.isNotEmpty ||
        entryDelta.added.isNotEmpty ||
        entryDelta.updated.isNotEmpty ||
        entryDelta.removed.isNotEmpty ||
        compositionDiffs.isNotEmpty;
    final nextRevision = _nextRevision(
      previousRevision,
      batch.slices.values,
      hasChanges: hasChanges,
    );

    final snapshotSlice = nextSlices[EnvironmentSliceKey.scene];
    if (snapshotSlice?.value case final ContextSnapshot snapshot) {
      nextSlices[EnvironmentSliceKey.scene] = snapshotSlice!;
      _state = EnvironmentState(
        snapshot: StateSlice<ContextSnapshot>(
          value: snapshot,
          revision: snapshotSlice.revision,
          observedAt: snapshotSlice.observedAt,
          expiresAt: snapshotSlice.expiresAt,
          freshness: snapshotSlice.freshness,
          sourceFingerprint: snapshotSlice.sourceFingerprint,
        ),
        entries: StateSlice<List<ContextEntry>>(
          value: _entryStore.current.entries.values.toList(growable: false),
          revision: _entryStore.current.revision,
          observedAt: snapshot.observedAt,
          expiresAt: snapshot.expiresAt,
          freshness: snapshotSlice.freshness,
          sourceFingerprint: 'entry-store:${_entryStore.current.revision}',
        ),
        slices: nextSlices,
        revision: nextRevision,
      );
    } else if (previous != null) {
      _state = EnvironmentState(
        snapshot: previous.snapshot,
        entries: StateSlice<List<ContextEntry>>(
          value: _entryStore.current.entries.values.toList(growable: false),
          revision: _entryStore.current.revision,
          observedAt: previous.entries.observedAt,
          expiresAt: previous.entries.expiresAt,
          freshness: previous.entries.freshness,
          sourceFingerprint: 'entry-store:${_entryStore.current.revision}',
        ),
        slices: nextSlices,
        revision: nextRevision,
      );
    }
    final resolvedRevision = _state?.revision ?? nextRevision;
    final delta = ContextDelta(
      transactionId: batch.transactionId,
      previousRevision: previousRevision,
      nextRevision: resolvedRevision,
      reason: batch.reason,
      changedSlices: changedSlices,
      addedEntries: entryDelta.added,
      updatedEntries: entryDelta.updated,
      removedEntries: entryDelta.removed,
      compositionDiffs: Map.unmodifiable(compositionDiffs),
    );
    if (hasChanges) {
      _changes.add(delta);
    }
    return delta;
  }

  static CompositionDiff _diffComposition(
    SurfaceComposition? previous,
    SurfaceComposition next,
    Set<EnvironmentSliceKey> changedSlices,
  ) {
    if (previous == null) {
      return CompositionDiff(
        inserted: next.slots.keys.toSet(),
        ambientChanged: changedSlices.contains(EnvironmentSliceKey.ambient),
        narrativeFactsChanged: next.narrativeFacts.isNotEmpty,
      );
    }
    final inserted = <CompositionSlot>{};
    final updated = <CompositionSlot>{};
    final removed = <CompositionSlot>{};
    final moved = <CompositionSlot>{};
    final previousSlotByEntryId = <String, CompositionSlot>{
      for (final item in previous.slots.entries) item.value.id: item.key,
    };

    for (final slot in next.slots.keys) {
      final oldEntry = previous.slots[slot];
      final nextEntry = next.slots[slot]!;
      if (oldEntry == null) {
        inserted.add(slot);
      } else if (oldEntry.id != nextEntry.id ||
          oldEntry.contentFingerprint != nextEntry.contentFingerprint) {
        updated.add(slot);
      }
      final oldSlot = previousSlotByEntryId[nextEntry.id];
      if (oldSlot != null && oldSlot != slot) moved.add(slot);
    }
    for (final slot in previous.slots.keys) {
      if (!next.slots.containsKey(slot)) removed.add(slot);
    }

    return CompositionDiff(
      inserted: inserted,
      updated: updated,
      removed: removed,
      moved: moved,
      ambientChanged: changedSlices.contains(EnvironmentSliceKey.ambient),
      narrativeFactsChanged:
          previous.narrativeFacts.length != next.narrativeFacts.length ||
          !previous.narrativeFacts.containsAll(next.narrativeFacts),
    );
  }

  static bool _hasCompositionChanges(CompositionDiff diff) =>
      diff.inserted.isNotEmpty ||
      diff.updated.isNotEmpty ||
      diff.removed.isNotEmpty ||
      diff.moved.isNotEmpty ||
      diff.ambientChanged ||
      diff.narrativeFactsChanged;

  static int _nextRevision(
    int previous,
    Iterable<StateSlice<Object?>> slices, {
    required bool hasChanges,
  }) {
    if (!hasChanges) return previous;
    var next = previous + 1;
    for (final slice in slices) {
      if (slice.revision > next) next = slice.revision;
    }
    return next;
  }
}
