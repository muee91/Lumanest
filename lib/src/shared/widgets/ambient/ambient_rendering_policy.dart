import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

class AmbientRendering {
  const AmbientRendering({
    required this.reduceMotion,
    required this.reduceFlashing,
    required this.showWeatherTexture,
  });

  final bool reduceMotion;
  final bool reduceFlashing;
  final bool showWeatherTexture;
}

abstract final class AmbientRenderingPolicy {
  static AmbientRendering resolve(
    ProfilePreferences preferences, {
    required bool conserveDeviceEnergy,
  }) {
    return switch (preferences.ambientMotionMode) {
      AmbientMotionMode.full when conserveDeviceEnergy =>
        const AmbientRendering(
          reduceMotion: true,
          reduceFlashing: true,
          showWeatherTexture: true,
        ),
      AmbientMotionMode.full => AmbientRendering(
        reduceMotion: preferences.reduceMotion,
        reduceFlashing: preferences.reduceFlashing,
        showWeatherTexture: true,
      ),
      AmbientMotionMode.energySaver => const AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: true,
      ),
      AmbientMotionMode.staticColor => const AmbientRendering(
        reduceMotion: true,
        reduceFlashing: true,
        showWeatherTexture: false,
      ),
    };
  }
}
