import 'dart:async';

import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/state/context_delta.dart';
import 'package:luma_nest/src/core/state/environment_state.dart';
import 'package:luma_nest/src/core/state/state_slice.dart';

class EnvironmentSliceBatch {
  const EnvironmentSliceBatch({
    required this.transactionId,
    required this.reason,
    required this.slices,
    required this.entries,
  });

  final String transactionId;
  final String reason;
  final Map<EnvironmentSliceKey, StateSlice<Object?>> slices;
  final EntryBatch entries;
}

class PartialRefreshController {
  PartialRefreshController({required this._entryStore});

  final ContextEntryStore _entryStore;
  final StreamController<ContextDelta> _changes =
      StreamController<ContextDelta>.broadcast(sync: true);
  EnvironmentState? _state;

  EnvironmentState? get state => _state;

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
        revision: _nextRevision(previousRevision, batch.slices.values),
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
        revision: _nextRevision(previousRevision, batch.slices.values),
      );
    }
    final nextRevision = _state?.revision ?? previousRevision;
    final delta = ContextDelta(
      transactionId: batch.transactionId,
      previousRevision: previousRevision,
      nextRevision: nextRevision,
      reason: batch.reason,
      changedSlices: changedSlices,
      addedEntries: entryDelta.added,
      updatedEntries: entryDelta.updated,
      removedEntries: entryDelta.removed,
      compositionDiffs: const {},
    );
    if (changedSlices.isNotEmpty ||
        entryDelta.added.isNotEmpty ||
        entryDelta.updated.isNotEmpty ||
        entryDelta.removed.isNotEmpty) {
      _changes.add(delta);
    }
    return delta;
  }

  static int _nextRevision(int previous, Iterable<StateSlice<Object?>> slices) {
    var next = previous;
    for (final slice in slices) {
      if (slice.revision > next) next = slice.revision;
    }
    return next;
  }
}
