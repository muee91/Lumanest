import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';

/// The deterministic visual parameters that turn an environment snapshot into
/// background behavior. This deliberately contains no AI-generated values.
class AmbientVisualState {
  const AmbientVisualState({
    required this.palette,
    required this.flowDirection,
    required this.motionIntensity,
    required this.precipitationIntensity,
    required this.thunderstorm,
  });

  final AmbientPalette palette;

  /// Meteorological direction in degrees, normalized to 0–360.
  final double flowDirection;

  /// Kept deliberately low so the background remains behind the information.
  final double motionIntensity;

  /// A 0–1 texture density, not a weather severity indicator.
  final double precipitationIntensity;
  final bool thunderstorm;
}

class AmbientPalette {
  const AmbientPalette({required this.topColor, required this.bottomColor});

  final Color topColor;
  final Color bottomColor;

  @override
  bool operator ==(Object other) =>
      other is AmbientPalette &&
      other.topColor == topColor &&
      other.bottomColor == bottomColor;

  @override
  int get hashCode => Object.hash(topColor, bottomColor);
}

class AmbientVisualMapper {
  const AmbientVisualMapper();

  static const _dayPhaseBlendRatio = 0.15;

  AmbientPalette resolve(
    WeatherType weather,
    DayPhase dayPhase,
    Brightness brightness,
  ) {
    final base = brightness == Brightness.dark
        ? _darkPalette(weather)
        : _lightPalette(weather);
    return _applyDayPhase(base, dayPhase);
  }

  AmbientVisualState resolveSnapshot(
    ContextSnapshot snapshot,
    Brightness brightness,
  ) {
    final wind = snapshot.windSpeedMetersPerSecond ?? 0;
    final rain = snapshot.precipitationMillimeters ?? 0;
    return AmbientVisualState(
      palette: resolve(snapshot.weather, snapshot.dayPhase, brightness),
      flowDirection: (snapshot.windDirectionDegrees ?? 0) % 360,
      motionIntensity: (0.08 + wind / 30).clamp(0.08, 0.4),
      precipitationIntensity: (rain / 8).clamp(0, 1),
      thunderstorm: snapshot.safetyEventIds.contains('thunderstorm'),
    );
  }

  static AmbientPalette _applyDayPhase(AmbientPalette base, DayPhase dayPhase) {
    final tint = _tintForDayPhase(dayPhase);
    if (tint == null) return base;
    return AmbientPalette(
      topColor: Color.lerp(base.topColor, tint, _dayPhaseBlendRatio)!,
      bottomColor: Color.lerp(base.bottomColor, tint, _dayPhaseBlendRatio)!,
    );
  }

  static Color? _tintForDayPhase(DayPhase dayPhase) {
    return switch (dayPhase) {
      DayPhase.dawn => const Color(0xFFFFC080),
      DayPhase.day => null,
      DayPhase.sunset => const Color(0xFFFF7043),
      DayPhase.blueHour => const Color(0xFF8090E0),
      DayPhase.night => null,
    };
  }

  static AmbientPalette _lightPalette(WeatherType weather) {
    return switch (weather) {
      WeatherType.clear => const AmbientPalette(
        topColor: Color(0xFFF0E6D3),
        bottomColor: Color(0xFFE8DCC8),
      ),
      WeatherType.cloudy => const AmbientPalette(
        topColor: Color(0xFFDCDBD6),
        bottomColor: Color(0xFFCFCEC8),
      ),
      WeatherType.rain => const AmbientPalette(
        topColor: Color(0xFFC4CDD6),
        bottomColor: Color(0xFFACB7C2),
      ),
      WeatherType.snow => const AmbientPalette(
        topColor: Color(0xFFE4EBF0),
        bottomColor: Color(0xFFD8E1E8),
      ),
      WeatherType.dust => const AmbientPalette(
        topColor: Color(0xFFE6DAC8),
        bottomColor: Color(0xFFD3C4A6),
      ),
    };
  }

  static AmbientPalette _darkPalette(WeatherType weather) {
    return switch (weather) {
      WeatherType.clear => const AmbientPalette(
        topColor: Color(0xFF1A1A2E),
        bottomColor: Color(0xFF0F0F1A),
      ),
      WeatherType.cloudy => const AmbientPalette(
        topColor: Color(0xFF262638),
        bottomColor: Color(0xFF181828),
      ),
      WeatherType.rain => const AmbientPalette(
        topColor: Color(0xFF1A1E28),
        bottomColor: Color(0xFF10141C),
      ),
      WeatherType.snow => const AmbientPalette(
        topColor: Color(0xFF1E2430),
        bottomColor: Color(0xFF161C26),
      ),
      WeatherType.dust => const AmbientPalette(
        topColor: Color(0xFF2C2620),
        bottomColor: Color(0xFF201C16),
      ),
    };
  }
}
