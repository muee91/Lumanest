import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_rendering_policy.dart';

void main() {
  test('device energy constraint downgrades full rendering', () {
    final rendering = AmbientRenderingPolicy.resolve(
      const ProfilePreferences(ambientMotionMode: AmbientMotionMode.full),
      conserveDeviceEnergy: true,
    );

    expect(rendering.reduceMotion, isTrue);
    expect(rendering.reduceFlashing, isTrue);
    expect(rendering.showWeatherTexture, isTrue);
  });

  test('device energy does not override a user-selected static mode', () {
    final rendering = AmbientRenderingPolicy.resolve(
      const ProfilePreferences(
        ambientMotionMode: AmbientMotionMode.staticColor,
      ),
      conserveDeviceEnergy: true,
    );

    expect(rendering.reduceMotion, isTrue);
    expect(rendering.reduceFlashing, isTrue);
    expect(rendering.showWeatherTexture, isFalse);
  });

  test('unknown device energy preserves the full user preferences', () {
    final rendering = AmbientRenderingPolicy.resolve(
      const ProfilePreferences(reduceMotion: false, reduceFlashing: true),
      conserveDeviceEnergy: false,
    );

    expect(rendering.reduceMotion, isFalse);
    expect(rendering.reduceFlashing, isTrue);
    expect(rendering.showWeatherTexture, isTrue);
  });

  test('route intensity follows the page hierarchy', () {
    expect(AmbientRenderingPolicy.intensityForRoute('/today'), 1.0);
    expect(AmbientRenderingPolicy.intensityForRoute('/inspiration'), 1.2);
    expect(AmbientRenderingPolicy.intensityForRoute('/explore'), 0.3);
    expect(AmbientRenderingPolicy.intensityForRoute('/route'), 0.15);
    expect(AmbientRenderingPolicy.intensityForRoute('/profile'), 0.0);
  });

  test('nested routes inherit their top-level intensity', () {
    expect(AmbientRenderingPolicy.intensityForRoute('/explore/search'), 0.3);
    expect(AmbientRenderingPolicy.intensityForRoute('/route/active'), 0.15);
  });
}
