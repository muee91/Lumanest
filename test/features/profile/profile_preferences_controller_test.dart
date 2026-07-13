import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/profile/infrastructure/profile_preferences_store.dart';

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
        expect(preferences.highContrast, isFalse);
        expect(preferences.ambientMotionMode, AmbientMotionMode.full);
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

  test('toggles and persists high contrast independently', () async {
    final store = _FakeProfilePreferencesStore(null);
    final contrastContainer = ProviderContainer(
      overrides: [profilePreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(contrastContainer.dispose);
    contrastContainer.read(profilePreferencesProvider);

    contrastContainer
        .read(profilePreferencesProvider.notifier)
        .toggleHighContrast();
    await Future<void>.delayed(Duration.zero);

    expect(
      contrastContainer.read(profilePreferencesProvider).highContrast,
      isTrue,
    );
    expect(store.value?.highContrast, isTrue);
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

  test('sets and persists the ambient performance mode', () async {
    final store = _FakeProfilePreferencesStore(null);
    final modeContainer = ProviderContainer(
      overrides: [profilePreferencesStoreProvider.overrideWithValue(store)],
    );
    addTearDown(modeContainer.dispose);
    modeContainer.read(profilePreferencesProvider);

    modeContainer
        .read(profilePreferencesProvider.notifier)
        .setAmbientMotionMode(AmbientMotionMode.energySaver);
    await Future<void>.delayed(Duration.zero);

    expect(
      modeContainer.read(profilePreferencesProvider).ambientMotionMode,
      AmbientMotionMode.energySaver,
    );
    expect(store.value?.ambientMotionMode, AmbientMotionMode.energySaver);
  });

  test('restores persisted accessibility preferences', () async {
    final restoredContainer = ProviderContainer(
      overrides: [
        profilePreferencesStoreProvider.overrideWithValue(
          _FakeProfilePreferencesStore(
            const ProfilePreferences(
              ambientBackgroundEnabled: false,
              reduceMotion: true,
              reduceFlashing: true,
              highContrast: true,
              ambientMotionMode: AmbientMotionMode.energySaver,
            ),
          ),
        ),
      ],
    );
    addTearDown(restoredContainer.dispose);

    restoredContainer.read(profilePreferencesProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      restoredContainer.read(profilePreferencesProvider),
      const ProfilePreferences(
        ambientBackgroundEnabled: false,
        reduceMotion: true,
        reduceFlashing: true,
        highContrast: true,
        ambientMotionMode: AmbientMotionMode.energySaver,
      ),
    );
  });
}

class _FakeProfilePreferencesStore implements ProfilePreferencesStore {
  _FakeProfilePreferencesStore(this.value);
  ProfilePreferences? value;

  @override
  Future<ProfilePreferences?> read() async => value;

  @override
  Future<void> write(ProfilePreferences value) async => this.value = value;
}
