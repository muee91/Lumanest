import 'package:luma_nest/src/core/entry/context_entry.dart';

enum CompositionSlot {
  blockingSafety,
  primary,
  secondaryA,
  secondaryB,
  companion,
  inlineSystem,
  mapHighlight,
  routeCritical,
}

class SurfaceComposition {
  SurfaceComposition({
    required this.id,
    required this.surface,
    required this.revision,
    required this.generatedAt,
    required Map<CompositionSlot, ContextEntry> slots,
    required this.judgement,
    required this.narrativeFacts,
  }) : slots = Map.unmodifiable(slots);

  final String id;
  final EntrySurface surface;
  final int revision;
  final DateTime generatedAt;
  final Map<CompositionSlot, ContextEntry> slots;
  final String judgement;
  final Set<String> narrativeFacts;

  ContextEntry? operator [](CompositionSlot slot) => slots[slot];
}
