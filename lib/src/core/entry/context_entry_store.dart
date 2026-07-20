import 'dart:async';

import 'package:luma_nest/src/core/entry/context_entry.dart';

class EntryBatch {
  const EntryBatch({
    required this.entries,
    required this.sourceRevision,
    this.removeIds = const {},
  });

  final Iterable<ContextEntry> entries;
  final int sourceRevision;
  final Iterable<String> removeIds;
}

class EntryStoreSnapshot {
  EntryStoreSnapshot({
    required this.revision,
    required Map<String, ContextEntry> entries,
  }) : entries = Map.unmodifiable(entries);

  final int revision;
  final Map<String, ContextEntry> entries;
}

class EntryDelta {
  EntryDelta({
    required this.previousRevision,
    required this.nextRevision,
    required Iterable<ContextEntry> added,
    required Iterable<ContextEntry> updated,
    required Iterable<ContextEntry> removed,
    required Iterable<ContextEntry> unchanged,
  }) : added = List.unmodifiable(added),
       updated = List.unmodifiable(updated),
       removed = List.unmodifiable(removed),
       unchanged = List.unmodifiable(unchanged);

  final int previousRevision;
  final int nextRevision;
  final List<ContextEntry> added;
  final List<ContextEntry> updated;
  final List<ContextEntry> removed;
  final List<ContextEntry> unchanged;
}

class EntryQuery {
  const EntryQuery({this.surface, this.kind});

  final EntrySurface? surface;
  final EntryKind? kind;
}

abstract interface class ContextEntryStore {
  EntryStoreSnapshot get current;
  Stream<EntryDelta> watch();
  EntryDelta apply(EntryBatch batch);
  ContextEntry? byId(String id);
  List<ContextEntry> query(EntryQuery query);
}

class InMemoryContextEntryStore implements ContextEntryStore {
  InMemoryContextEntryStore()
    : _current = EntryStoreSnapshot(revision: 0, entries: const {});

  final StreamController<EntryDelta> _changes =
      StreamController<EntryDelta>.broadcast(sync: true);
  EntryStoreSnapshot _current;

  @override
  EntryStoreSnapshot get current => _current;

  @override
  Stream<EntryDelta> watch() => _changes.stream;

  @override
  EntryDelta apply(EntryBatch batch) {
    final previous = _current;
    final candidate = <String, ContextEntry>{...previous.entries};
    final touched = <String>{};
    for (final entry in batch.entries) {
      if (entry.id.isEmpty ||
          entry.sourceId.isEmpty ||
          entry.isExpiredAt(DateTime.now())) {
        continue;
      }
      final existing = previous.entries[entry.id];
      if (existing != null && entry.revision < existing.revision) continue;
      candidate[entry.id] = entry;
      touched.add(entry.id);
    }
    final requestedRemovals = batch.removeIds.toSet();
    candidate.removeWhere((id, _) => requestedRemovals.contains(id));

    final added = <ContextEntry>[];
    final updated = <ContextEntry>[];
    final unchanged = <ContextEntry>[];
    for (final id in touched) {
      final entry = candidate[id];
      if (entry == null) continue;
      final existing = previous.entries[entry.id];
      if (existing == null) {
        added.add(entry);
      } else if (entry.revision > existing.revision ||
          entry.contentFingerprint != existing.contentFingerprint) {
        updated.add(entry);
      } else {
        unchanged.add(existing);
      }
    }
    final removed = previous.entries.values
        .where((entry) => requestedRemovals.contains(entry.id))
        .toList(growable: false);
    final changed =
        added.isNotEmpty || updated.isNotEmpty || removed.isNotEmpty;
    final nextRevision = changed
        ? (batch.sourceRevision > previous.revision
              ? batch.sourceRevision
              : previous.revision + 1)
        : previous.revision;
    final delta = EntryDelta(
      previousRevision: previous.revision,
      nextRevision: nextRevision,
      added: added,
      updated: updated,
      removed: removed,
      unchanged: unchanged,
    );
    if (changed) {
      _current = EntryStoreSnapshot(revision: nextRevision, entries: candidate);
      _changes.add(delta);
    }
    return delta;
  }

  @override
  ContextEntry? byId(String id) => _current.entries[id];

  @override
  List<ContextEntry> query(EntryQuery query) => _current.entries.values
      .where((entry) => query.kind == null || entry.kind == query.kind)
      .where(
        (entry) =>
            query.surface == null ||
            entry.allowedSurfaces.contains(query.surface),
      )
      .toList(growable: false);
}
