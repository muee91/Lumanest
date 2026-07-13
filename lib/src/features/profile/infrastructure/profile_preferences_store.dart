import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ProfilePreferencesStore {
  Future<ProfilePreferences?> read();
  Future<void> write(ProfilePreferences value);
}

class SharedPreferencesProfilePreferencesStore
    implements ProfilePreferencesStore {
  SharedPreferencesProfilePreferencesStore(this._preferences);

  static const _key = 'profile_preferences_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<ProfilePreferences?> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw);
      if (body is! Map || body['version'] != 1) return null;
      final ambient = body['ambientBackgroundEnabled'];
      final motion = body['reduceMotion'];
      final flashing = body['reduceFlashing'];
      final highContrast = body['highContrast'];
      final ambientMotionMode = body['ambientMotionMode'];
      if (ambient is! bool || motion is! bool || flashing is! bool) return null;
      return ProfilePreferences(
        ambientBackgroundEnabled: ambient,
        reduceMotion: motion,
        reduceFlashing: flashing,
        highContrast: highContrast is bool ? highContrast : false,
        ambientMotionMode: _decodeAmbientMotionMode(ambientMotionMode),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(ProfilePreferences value) {
    return _preferences.setString(
      _key,
      jsonEncode({
        'version': 1,
        'ambientBackgroundEnabled': value.ambientBackgroundEnabled,
        'reduceMotion': value.reduceMotion,
        'reduceFlashing': value.reduceFlashing,
        'highContrast': value.highContrast,
        'ambientMotionMode': value.ambientMotionMode.name,
      }),
    );
  }

  AmbientMotionMode _decodeAmbientMotionMode(Object? value) {
    if (value is! String) return AmbientMotionMode.full;
    return AmbientMotionMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AmbientMotionMode.full,
    );
  }
}

final profilePreferencesStoreProvider = Provider<ProfilePreferencesStore>((
  ref,
) {
  return SharedPreferencesProfilePreferencesStore(SharedPreferencesAsync());
});
