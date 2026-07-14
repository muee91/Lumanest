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
    required this.cloudOpacity,
    required this.gustFactor,
    required this.warmGlow,
  });

  final AmbientPalette palette;

  /// Meteorological direction in degrees, normalized to 0–360.
  final double flowDirection;

  /// Kept deliberately low so the background remains behind the information.
  final double motionIntensity;

  /// A 0–1 texture density, not a weather severity indicator.
  final double precipitationIntensity;
  final bool thunderstorm;

  /// Grayscale overlay opacity (0.0–0.4) derived from cloud cover. Higher
  /// cloud cover desaturates the palette and lowers contrast so dense skies
  /// read as flatter, duller backgrounds.
  final double cloudOpacity;

  /// Estimated gust disturbance factor (0.0–1.0). When the data source lacks
  /// a measured gust speed this is derived from the weather type and mean
  /// wind, and drives occasional motion surges in the canvas.
  final double gustFactor;

  /// Warm alpenglow渗透强度 (0.0–1.0). Active around dawn/sunset with
  /// relatively clear skies, it controls how strongly warm tones bleed into
  /// the ambient palette.
  final double warmGlow;
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
    final cloudCover =
        snapshot.cloudCoverPercent ?? _estimatedCloudCover(snapshot.weather);
    return AmbientVisualState(
      palette: resolve(snapshot.weather, snapshot.dayPhase, brightness),
      flowDirection: (snapshot.windDirectionDegrees ?? 0) % 360,
      motionIntensity: (0.08 + wind / 30).clamp(0.08, 0.4),
      precipitationIntensity: (rain / 8).clamp(0, 1),
      thunderstorm: snapshot.safetyEventIds.contains('thunderstorm'),
      cloudOpacity: (cloudCover / 100 * 0.4).clamp(0.0, 0.4),
      gustFactor: _estimateGustFactor(snapshot.weather, wind),
      warmGlow: _resolveWarmGlow(
        snapshot.weather,
        snapshot.dayPhase,
        cloudCover,
      ),
    );
  }

  /// Fallback cloud cover when the snapshot does not carry a measurement so
  /// the grayscale mapping still reacts to the weather type.
  static double _estimatedCloudCover(WeatherType weather) {
    return switch (weather) {
      WeatherType.clear => 10,
      WeatherType.cloudy => 75,
      WeatherType.rain => 90,
      WeatherType.snow => 85,
      WeatherType.dust => 20,
    };
  }

  /// Estimates a gust disturbance factor in the absence of a measured gust
  /// speed. Turbulent weather (dust/rain) raises the baseline and stronger
  /// mean wind increases the chance of a spike, clamped to 0–1.
  static double _estimateGustFactor(WeatherType weather, double wind) {
    final base = switch (weather) {
      WeatherType.clear => 0.10,
      WeatherType.cloudy => 0.20,
      WeatherType.rain => 0.45,
      WeatherType.snow => 0.30,
      WeatherType.dust => 0.60,
    };
    return (base + wind / 40).clamp(0.0, 1.0);
  }

  /// Resolves the alpenglow warm渗透 factor. Alpenglow only appears during
  /// the golden phases (dawn/sunset) and needs a relatively clear sky; rain
  /// and snow suppress it entirely, and increasing cloud cover dims it.
  static double _resolveWarmGlow(
    WeatherType weather,
    DayPhase dayPhase,
    double cloudCover,
  ) {
    final golden = dayPhase == DayPhase.dawn || dayPhase == DayPhase.sunset;
    if (!golden) return 0.0;
    if (cloudCover > 40) return 0.0;
    final base = switch (weather) {
      WeatherType.clear => 1.0,
      WeatherType.cloudy => 0.5,
      WeatherType.dust => 0.3,
      WeatherType.rain => 0.0,
      WeatherType.snow => 0.0,
    };
    final cloudDim = (cloudCover / 40).clamp(0.0, 1.0);
    return (base * (1 - cloudDim * 0.6)).clamp(0.0, 1.0);
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
