import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';
import 'package:luma_nest/src/core/state/environment_state.dart';

class CompositionDiff {
  const CompositionDiff({
    this.inserted = const {},
    this.updated = const {},
    this.removed = const {},
    this.moved = const {},
    this.ambientChanged = false,
    this.narrativeFactsChanged = false,
  });

  final Set<CompositionSlot> inserted;
  final Set<CompositionSlot> updated;
  final Set<CompositionSlot> removed;
  final Set<CompositionSlot> moved;
  final bool ambientChanged;
  final bool narrativeFactsChanged;
}

class ContextDelta {
  const ContextDelta({
    required this.transactionId,
    required this.previousRevision,
    required this.nextRevision,
    required this.reason,
    required this.changedSlices,
    required this.addedEntries,
    required this.updatedEntries,
    required this.removedEntries,
    required this.compositionDiffs,
  });

  final String transactionId;
  final int previousRevision;
  final int nextRevision;
  final String reason;
  final Set<EnvironmentSliceKey> changedSlices;
  final List<ContextEntry> addedEntries;
  final List<ContextEntry> updatedEntries;
  final List<ContextEntry> removedEntries;
  final Map<EntrySurface, CompositionDiff> compositionDiffs;
}
