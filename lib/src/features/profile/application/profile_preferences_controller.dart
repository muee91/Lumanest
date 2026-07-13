import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/profile_preferences.dart';
import '../infrastructure/profile_preferences_store.dart';

/// Restores persisted accessibility preferences without delaying first paint.
class ProfilePreferencesController extends Notifier<ProfilePreferences> {
  var _changedThisSession = false;

  @override
  ProfilePreferences build() {
    unawaited(_restore());
    return const ProfilePreferences();
  }

  Future<void> _restore() async {
    final restored = await ref.read(profilePreferencesStoreProvider).read();
    if (!_changedThisSession && restored != null) state = restored;
  }

  void toggleAmbientBackground() {
    _update(
      state.copyWith(ambientBackgroundEnabled: !state.ambientBackgroundEnabled),
    );
  }

  void toggleReduceMotion() {
    _update(state.copyWith(reduceMotion: !state.reduceMotion));
  }

  void toggleReduceFlashing() {
    _update(state.copyWith(reduceFlashing: !state.reduceFlashing));
  }

  void toggleHighContrast() {
    _update(state.copyWith(highContrast: !state.highContrast));
  }

  void setAmbientMotionMode(AmbientMotionMode mode) {
    _update(state.copyWith(ambientMotionMode: mode));
  }

  void _update(ProfilePreferences value) {
    _changedThisSession = true;
    state = value;
    unawaited(ref.read(profilePreferencesStoreProvider).write(value));
  }
}

/// Provides the current [ProfilePreferences] and its controller.
final profilePreferencesProvider =
    NotifierProvider<ProfilePreferencesController, ProfilePreferences>(
      ProfilePreferencesController.new,
    );
