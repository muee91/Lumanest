import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class EnvironmentConsentStore {
  Future<bool?> readGranted();

  Future<void> saveGranted();
}

class SharedPreferencesEnvironmentConsentStore
    implements EnvironmentConsentStore {
  SharedPreferencesEnvironmentConsentStore(this._preferences);

  static const _key = 'environment_data_consent_granted';
  final SharedPreferencesAsync _preferences;

  @override
  Future<bool?> readGranted() => _preferences.getBool(_key);

  @override
  Future<void> saveGranted() => _preferences.setBool(_key, true);
}

final environmentConsentStoreProvider = Provider<EnvironmentConsentStore>((
  ref,
) {
  return SharedPreferencesEnvironmentConsentStore(SharedPreferencesAsync());
});

/// Controls whether the app may begin loading current-location environment
/// data. This is distinct from the operating system location permission:
/// users opt in here first, then the platform may ask for location access.
class EnvironmentConsentController extends Notifier<bool> {
  var _grantedThisSession = false;

  @override
  bool build() {
    unawaited(_restore());
    return false;
  }

  Future<void> _restore() async {
    final restored = await ref
        .read(environmentConsentStoreProvider)
        .readGranted();
    if (!_grantedThisSession && restored == true) state = true;
  }

  void grant() {
    _grantedThisSession = true;
    state = true;
    unawaited(ref.read(environmentConsentStoreProvider).saveGranted());
  }
}

final environmentConsentProvider =
    NotifierProvider<EnvironmentConsentController, bool>(
      EnvironmentConsentController.new,
    );
