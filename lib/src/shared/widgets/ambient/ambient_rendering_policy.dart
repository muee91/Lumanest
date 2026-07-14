import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

class AmbientRendering {
  const AmbientRendering({
    required this.reduceMotion,
    required this.reduceFlashing,
    required this.showWeatherTexture,
    this.intensity = 1.0,
  });

  final bool reduceMotion;
  final bool reduceFlashing;
  final bool showWeatherTexture;

  /// Page-level ambient strength (0.0 = static, 1.0 = full). The inspiration
  /// page may exceed 1.0 to render an enhanced reflective look per design
  /// §9.2.
  final double intensity;
}

abstract final class AmbientRenderingPolicy {
  static AmbientRendering resolve(
    ProfilePreferences preferences, {
    required bool conserveDeviceEnergy,
    String? routeLocation,
  }) {
    final intensity = intensityForRoute(routeLocation);
    return switch (preferences.ambientMotionMode) {
      AmbientMotionMode.full when conserveDeviceEnergy => AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: true,
        intensity: intensity,
      ),
      AmbientMotionMode.full => AmbientRendering(
        reduceMotion: preferences.reduceMotion,
        reduceFlashing: preferences.reduceFlashing,
        showWeatherTexture: true,
        intensity: intensity,
      ),
      AmbientMotionMode.energySaver => AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: true,
        intensity: intensity,
      ),
      AmbientMotionMode.staticColor => AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: false,
        intensity: intensity,
      ),
    };
  }

  /// Resolves the ambient intensity for the current route per design §9.2.
  ///
  /// - 今日 (/today): 1.0 (full but low-saturation environment field)
  /// - 灵感 (/inspiration): 1.2 (enhanced, the glass bottle inherits reflections)
  /// - 探索 (/explore): 0.3 (edges only)
  /// - 路线 (/route): 0.15 (slight color band)
  /// - 我的 (/profile): 0.0 (basically static)
  static double intensityForRoute(String? location) {
    if (location == null) return 1.0;
    if (location.startsWith('/today')) return 1.0;
    if (location.startsWith('/inspiration')) return 1.2;
    if (location.startsWith('/explore')) return 0.3;
    if (location.startsWith('/route')) return 0.15;
    if (location.startsWith('/profile')) return 0.0;
    // Shooting window inherits the today branch's full ambiance.
    if (location.startsWith('/shooting-window')) return 1.0;
    return 1.0;
  }
}
