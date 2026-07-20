import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

class AmbientComposer {
  const AmbientComposer();

  AmbientVisualComposition compose({
    required AmbientVisualState visualState,
    required AmbientPreset preset,
    required AmbientQualityTier quality,
  }) {
    final base = preset.fieldFor(quality);
    final motion = visualState.motionIntensity.clamp(.08, .4);
    final motionProgress = ((motion - .08) / .32).clamp(0.0, 1.0);
    final storm = visualState.stormFactor.clamp(0.0, 1.0);
    final warmAccent = Color.lerp(
      visualState.accentColor,
      const Color(0xFFFF984D),
      (visualState.warmGlow * .82).clamp(0.0, .82),
    )!;
    final qualityMotion = switch (quality) {
      AmbientQualityTier.full ||
      AmbientQualityTier.balanced => motion.clamp(.08, .35),
      AmbientQualityTier.reduced => math.min(base.timeSpeed, .08),
      AmbientQualityTier.static => 0.0,
    };
    final semanticField = base.copyWith(
      colors: [
        visualState.palette.topColor,
        warmAccent,
        visualState.palette.bottomColor,
      ],
      timeSpeed: qualityMotion,
      blendAngleDegrees: _normalizeSignedDegrees(visualState.flowDirection),
      warpStrength: quality == AmbientQualityTier.static
          ? 0
          : (base.warpStrength *
                (.65 + motionProgress * .35 + storm * .35))
              .clamp(0.0, 2.1),
      saturation: (base.saturation - visualState.cloudOpacity * .35 - storm * .12)
          .clamp(.72, 1.16),
      contrast: (base.contrast - visualState.cloudOpacity * .12 - storm * .06)
          .clamp(.92, 1.18),
      animateGrain: quality == AmbientQualityTier.full && base.animateGrain,
    );
    AmbientPresetValidator.validateField(
      semanticField,
      path: '${preset.id}.composed',
    );
    return AmbientVisualComposition(
      semanticState: visualState,
      field: semanticField,
      quality: quality,
      transitionDuration: preset.transitionDuration,
    );
  }

  double _normalizeSignedDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized > 180 ? normalized - 360 : normalized;
  }
}
