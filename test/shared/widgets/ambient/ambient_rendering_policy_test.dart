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
}
