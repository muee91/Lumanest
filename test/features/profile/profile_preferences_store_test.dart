import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/profile/infrastructure/profile_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storageKey = 'profile_preferences_v1';

  test('round-trips the ambient performance mode', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.clear();
    final store = SharedPreferencesProfilePreferencesStore(preferences);

    await store.write(
      const ProfilePreferences(
        ambientMotionMode: AmbientMotionMode.staticColor,
      ),
    );

    expect(
      (await store.read())?.ambientMotionMode,
      AmbientMotionMode.staticColor,
    );
  });

  test('old version-one data without a mode defaults to full', () async {
    final preferences = SharedPreferencesAsync();
    await preferences.clear();
    await preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'ambientBackgroundEnabled': true,
        'reduceMotion': false,
        'reduceFlashing': false,
      }),
    );
    final store = SharedPreferencesProfilePreferencesStore(preferences);

    expect((await store.read())?.ambientMotionMode, AmbientMotionMode.full);
  });
}
