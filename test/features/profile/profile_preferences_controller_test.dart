import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('defaults', () {
    test(
      'enables ambient background and disables reduced motion and flashing',
      () {
        final preferences = container.read(profilePreferencesProvider);

        expect(preferences.ambientBackgroundEnabled, isTrue);
        expect(preferences.reduceMotion, isFalse);
        expect(preferences.reduceFlashing, isFalse);
      },
    );
  });

  group('toggleAmbientBackground', () {
    test('returns an immutable new state with the flag flipped', () {
      final controller = container.read(profilePreferencesProvider.notifier);
      final before = container.read(profilePreferencesProvider);

      controller.toggleAmbientBackground();

      final after = container.read(profilePreferencesProvider);

      expect(after.ambientBackgroundEnabled, isFalse);
      expect(
        before.ambientBackgroundEnabled,
        isTrue,
        reason: 'original state must remain unchanged',
      );
      expect(
        identical(before, after),
        isFalse,
        reason: 'toggle must produce a new instance',
      );
      expect(before.reduceMotion, equals(after.reduceMotion));
      expect(before.reduceFlashing, equals(after.reduceFlashing));
    });
  });

  group('toggleReduceMotion', () {
    test('returns an immutable new state with the flag flipped', () {
      final controller = container.read(profilePreferencesProvider.notifier);
      final before = container.read(profilePreferencesProvider);

      controller.toggleReduceMotion();

      final after = container.read(profilePreferencesProvider);

      expect(after.reduceMotion, isTrue);
      expect(
        before.reduceMotion,
        isFalse,
        reason: 'original state must remain unchanged',
      );
      expect(
        identical(before, after),
        isFalse,
        reason: 'toggle must produce a new instance',
      );
      expect(
        before.ambientBackgroundEnabled,
        equals(after.ambientBackgroundEnabled),
      );
      expect(before.reduceFlashing, equals(after.reduceFlashing));
    });
  });

  group('toggleReduceFlashing', () {
    test('returns an immutable new state with the flag flipped', () {
      final controller = container.read(profilePreferencesProvider.notifier);
      final before = container.read(profilePreferencesProvider);

      controller.toggleReduceFlashing();

      final after = container.read(profilePreferencesProvider);

      expect(after.reduceFlashing, isTrue);
      expect(
        before.reduceFlashing,
        isFalse,
        reason: 'original state must remain unchanged',
      );
      expect(
        identical(before, after),
        isFalse,
        reason: 'toggle must produce a new instance',
      );
      expect(
        before.ambientBackgroundEnabled,
        equals(after.ambientBackgroundEnabled),
      );
      expect(before.reduceMotion, equals(after.reduceMotion));
    });
  });

  test('ProfilePreferences equality treats matching fields as equal', () {
    const a = ProfilePreferences();
    const b = ProfilePreferences(
      ambientBackgroundEnabled: true,
      reduceMotion: false,
      reduceFlashing: false,
    );

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });
}
