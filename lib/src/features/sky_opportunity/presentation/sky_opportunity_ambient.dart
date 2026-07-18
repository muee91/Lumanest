import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

class SkyOpportunityAmbientMapper {
  const SkyOpportunityAmbientMapper();

  AmbientVisualState apply({
    required AmbientVisualState base,
    required ContextSnapshot snapshot,
    required SkyOpportunityForecast? forecast,
  }) {
    if (snapshot.safetyEventIds.isNotEmpty || forecast == null) return base;
    final strength = forecast.presentation.ambientStrength
        .clamp(0.0, .25)
        .toDouble();
    if (strength <= 0) return base;
    final highLightLevels = {'very_strong', 'excellent', 'rare', 'exceptional'};
    final clearOpportunityLevels = {'good', 'strong'};
    final targetTop = highLightLevels.contains(forecast.level)
        ? const Color(0xFFFF5D86)
        : clearOpportunityLevels.contains(forecast.level)
        ? const Color(0xFFFF8B52)
        : const Color(0xFFFFB0A2);
    final targetBottom = highLightLevels.contains(forecast.level)
        ? const Color(0xFFFFB64C)
        : clearOpportunityLevels.contains(forecast.level)
        ? const Color(0xFFFFBF61)
        : const Color(0xFFFFD0BE);
    return AmbientVisualState(
      palette: AmbientPalette(
        topColor: Color.lerp(base.palette.topColor, targetTop, strength)!,
        bottomColor: Color.lerp(
          base.palette.bottomColor,
          targetBottom,
          strength,
        )!,
      ),
      flowDirection: base.flowDirection,
      motionIntensity: base.motionIntensity,
      precipitationIntensity: base.precipitationIntensity,
      thunderstorm: base.thunderstorm,
      cloudOpacity: base.cloudOpacity,
      gustFactor: base.gustFactor,
      warmGlow: base.warmGlow,
      precipitation: base.precipitation,
      accentColor: Color.lerp(base.accentColor, targetTop, strength)!,
    );
  }
}
