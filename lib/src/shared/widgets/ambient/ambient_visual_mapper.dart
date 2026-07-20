import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';

/// The deterministic visual parameters that turn an environment snapshot into
/// background behavior. This deliberately contains no AI-generated values.
class AmbientVisualState {
  const AmbientVisualState({
    required this.weather,
    required this.dayPhase,
    required this.palette,
    required this.flowDirection,
    required this.motionIntensity,
    required this.precipitationIntensity,
    required this.thunderstorm,
    required this.cloudOpacity,
    required this.gustFactor,
    required this.warmGlow,
    required this.precipitation,
    required this.accentColor,
    required this.stormFactor,
    required this.glassBlur,
  });

  final WeatherType weather;
  final DayPhase dayPhase;

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

  /// The texture is visual-only and derived from deterministic weather data.
  final AmbientPrecipitation precipitation;

  /// A restrained scene color for the fragment field; never an AI value.
  final Color accentColor;

  /// Typhoon-class storm strength (0.0–1.0). Derived from sustained wind
  /// speed at or above the 8-grade threshold (17.2 m/s) combined with rain.
  /// Drives a rotating spiral field with a calm eye in the shader.
  final double stormFactor;

  /// Foreground glass blur amount (0.0–1.0). Composed from precipitation
  /// intensity, cloud opacity and storm factor so every weather kind can
  /// soften the scene through one shared lens-layer without discrete drops.
  final double glassBlur;

  double get flowRadians => flowDirection * 3.141592653589793 / 180;

  @override
  bool operator ==(Object other) {
    return other is AmbientVisualState &&
        other.weather == weather &&
        other.dayPhase == dayPhase &&
        other.palette == palette &&
        other.flowDirection == flowDirection &&
        other.motionIntensity == motionIntensity &&
        other.precipitationIntensity == precipitationIntensity &&
        other.thunderstorm == thunderstorm &&
        other.cloudOpacity == cloudOpacity &&
        other.gustFactor == gustFactor &&
        other.warmGlow == warmGlow &&
        other.precipitation == precipitation &&
        other.accentColor == accentColor &&
        other.stormFactor == stormFactor &&
        other.glassBlur == glassBlur;
  }

  @override
  int get hashCode => Object.hash(
    weather,
    dayPhase,
    palette,
    flowDirection,
    motionIntensity,
    precipitationIntensity,
    thunderstorm,
    cloudOpacity,
    gustFactor,
    warmGlow,
    precipitation,
    accentColor,
    stormFactor,
    glassBlur,
  );
}

enum AmbientPrecipitation { none, rain, snow }

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

  static const _dayPhaseBlendRatio = 0.32;
  static const _sceneBlendRatio = 0.06;

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
    final precipitationIntensity = _precipitationIntensity(
      snapshot.weather,
      rain,
    );
    final stormFactor = _estimateStormFactor(snapshot.weather, wind);
    return AmbientVisualState(
      weather: snapshot.weather,
      dayPhase: snapshot.dayPhase,
      palette: _applySceneAccent(
        resolve(snapshot.weather, snapshot.dayPhase, brightness),
        snapshot.primaryScene,
      ),
      flowDirection: (snapshot.windDirectionDegrees ?? 0) % 360,
      motionIntensity: (0.08 + wind / 30).clamp(0.08, 0.4),
      precipitationIntensity: precipitationIntensity,
      thunderstorm: snapshot.safetyEventIds.contains('thunderstorm'),
      cloudOpacity: (cloudCover / 100 * 0.4).clamp(0.0, 0.4),
      gustFactor: _estimateGustFactor(snapshot.weather, wind),
      warmGlow: _resolveWarmGlow(
        snapshot.weather,
        snapshot.dayPhase,
        cloudCover,
      ),
      precipitation: switch (snapshot.weather) {
        WeatherType.rain => AmbientPrecipitation.rain,
        WeatherType.snow => AmbientPrecipitation.snow,
        _ => AmbientPrecipitation.none,
      },
      accentColor: _accentForScene(snapshot.primaryScene),
      stormFactor: stormFactor,
      glassBlur: _resolveGlassBlur(
        precipitationIntensity,
        (cloudCover / 100 * 0.4).clamp(0.0, 0.4),
        stormFactor,
      ),
    );
  }

  static double _precipitationIntensity(WeatherType weather, double rain) {
    final measured = (rain / 8).clamp(0.0, 1.0);
    return switch (weather) {
      WeatherType.rain => measured < .32 ? .32 : measured,
      WeatherType.snow => measured < .24 ? .24 : measured,
      _ => measured,
    };
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
      WeatherType.unknown => 50,
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
      WeatherType.unknown => 0.15,
    };
    return (base + wind / 40).clamp(0.0, 1.0);
  }

  /// Typhoon-class storm factor. Active only when rain is falling and the
  /// sustained wind crosses the Beaufort 8 threshold (17.2 m/s). The shader
  /// uses this to drive a rotating spiral field with a calm eye; ordinary
  /// rain or wind never triggers it.
  static double _estimateStormFactor(WeatherType weather, double wind) {
    if (weather != WeatherType.rain) return 0.0;
    const threshold = 17.2;
    if (wind <= threshold) return 0.0;
    return ((wind - threshold) / 30.0).clamp(0.0, 1.0);
  }

  /// Foreground glass blur composed from precipitation, cloud and storm so a
  /// single lens-layer softens every weather kind. Rain contributes the
  /// strongest cue, cloud adds a haze baseline and storm amplifies both.
  static double _resolveGlassBlur(
    double precipitationIntensity,
    double cloudOpacity,
    double stormFactor,
  ) {
    final base = precipitationIntensity * 0.55 + cloudOpacity * 1.5;
    final amplified = base + stormFactor * 0.25;
    return amplified.clamp(0.0, 1.0);
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
      WeatherType.unknown => 0.0,
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

  /// Adds a deliberately subtle scene accent after weather and daylight have
  /// established the authoritative palette. This keeps the seven V1 contexts
  /// perceptibly distinct without turning scene labels into weather facts.
  static AmbientPalette _applySceneAccent(
    AmbientPalette base,
    SceneType scene,
  ) {
    final accent = switch (scene) {
      SceneType.unknown => null,
      SceneType.city => const Color(0xFF718096),
      SceneType.lake => const Color(0xFF3E9296),
      SceneType.mountain => const Color(0xFF8A7668),
      SceneType.desert => const Color(0xFFC28745),
      SceneType.village => const Color(0xFFAA6654),
    };
    if (accent == null) return base;
    return AmbientPalette(
      topColor: Color.lerp(base.topColor, accent, _sceneBlendRatio)!,
      bottomColor: Color.lerp(base.bottomColor, accent, _sceneBlendRatio)!,
    );
  }

  static Color _accentForScene(SceneType scene) => switch (scene) {
    SceneType.unknown => const Color(0xFF356C88),
    SceneType.city => const Color(0xFF718096),
    SceneType.lake => const Color(0xFF3E9296),
    SceneType.mountain => const Color(0xFF8A7668),
    SceneType.desert => const Color(0xFFC28745),
    SceneType.village => const Color(0xFFAA6654),
  };

  static AmbientPalette _lightPalette(WeatherType weather) {
    return switch (weather) {
      WeatherType.clear => const AmbientPalette(
        topColor: Color(0xFFCDE5EC),
        bottomColor: Color(0xFFF1E9DA),
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
      WeatherType.unknown => const AmbientPalette(
        topColor: Color(0xFFD7DEE0),
        bottomColor: Color(0xFFCBCFCD),
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
      WeatherType.unknown => const AmbientPalette(
        topColor: Color(0xFF242932),
        bottomColor: Color(0xFF171B22),
      ),
    };
  }
}
