import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/profile_preferences.dart';

/// In-memory controller for [ProfilePreferences].
///
/// Phase 1 holds state only for the lifetime of the provider; persistence is
/// deferred to a later Drift-backed phase. Every toggle produces a new
/// immutable state.
class ProfilePreferencesController extends Notifier<ProfilePreferences> {
  @override
  ProfilePreferences build() => const ProfilePreferences();

  void toggleAmbientBackground() {
    state = state.copyWith(
      ambientBackgroundEnabled: !state.ambientBackgroundEnabled,
    );
  }

  void toggleReduceMotion() {
    state = state.copyWith(reduceMotion: !state.reduceMotion);
  }

  void toggleReduceFlashing() {
    state = state.copyWith(reduceFlashing: !state.reduceFlashing);
  }
}

/// Provides the current [ProfilePreferences] and its controller.
final profilePreferencesProvider =
    NotifierProvider<ProfilePreferencesController, ProfilePreferences>(
      ProfilePreferencesController.new,
    );
