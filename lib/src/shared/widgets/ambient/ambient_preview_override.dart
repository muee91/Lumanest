import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';

/// Debug-only bridge between Ambient Studio and the real Today composition.
/// It is intentionally in-memory and never persisted or used by release builds.
@immutable
class AmbientPreviewOverride {
  const AmbientPreviewOverride({
    required this.snapshot,
    required this.composition,
    required this.label,
  });

  final ContextSnapshot snapshot;
  final AmbientVisualComposition composition;
  final String label;
}

class AmbientPreviewOverrideController
    extends Notifier<AmbientPreviewOverride?> {
  @override
  AmbientPreviewOverride? build() => null;

  void set(AmbientPreviewOverride value) => state = value;

  void clear() => state = null;
}

final ambientPreviewOverrideProvider =
    NotifierProvider<AmbientPreviewOverrideController, AmbientPreviewOverride?>(
      AmbientPreviewOverrideController.new,
    );
