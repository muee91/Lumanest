import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

enum AmbientRenderer { fragment, reducedFragment, staticField }

class AmbientRendering {
  const AmbientRendering({
    required this.reduceMotion,
    required this.reduceFlashing,
    required this.showWeatherTexture,
    required this.renderer,
    this.intensity = 1.0,
  });

  final bool reduceMotion;
  final bool reduceFlashing;
  final bool showWeatherTexture;
  final AmbientRenderer renderer;

  /// Page-level ambient strength (0.0 = static, 1.0 = full).
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
        renderer: AmbientRenderer.reducedFragment,
        intensity: intensity,
      ),
      AmbientMotionMode.full => AmbientRendering(
        reduceMotion: preferences.reduceMotion,
        reduceFlashing: preferences.reduceFlashing,
        showWeatherTexture: true,
        renderer: preferences.reduceMotion
            ? AmbientRenderer.reducedFragment
            : AmbientRenderer.fragment,
        intensity: intensity,
      ),
      AmbientMotionMode.energySaver => AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: true,
        renderer: AmbientRenderer.reducedFragment,
        intensity: intensity,
      ),
      AmbientMotionMode.staticColor => AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: false,
        renderer: AmbientRenderer.staticField,
        intensity: intensity,
      ),
    };
  }

  /// Resolves the ambient intensity for the current route per design §9.2.
  ///
  /// Only Today owns the dynamic environment field. Every other route is
  /// static and does not keep a hidden GPU animation alive behind its page.
  static double intensityForRoute(String? location) {
    if (location == null) return 0.0;
    if (location.startsWith('/today')) return 1.0;
    return 0.0;
  }
}
