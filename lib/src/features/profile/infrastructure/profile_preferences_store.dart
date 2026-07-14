import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
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
        photographyPreferences: _decodeStringSet(
          body['photographyPreferences'],
        ),
        activityPreferences: _decodeStringSet(body['activityPreferences']),
        equipmentList: body['equipmentList'] is String
            ? body['equipmentList'] as String
            : '',
        aiTone: _decodeAiTone(body['aiTone']),
        recommendationIntensity: body['recommendationIntensity'] is num
            ? (body['recommendationIntensity'] as num).toDouble()
            : 0.5,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(ProfilePreferences value) {
    final legacyPhotography = value.photographyPreferences.toList()..sort();
    final legacyActivities = value.activityPreferences.toList()..sort();
    return _preferences.setString(
      _key,
      jsonEncode({
        'version': 1,
        'ambientBackgroundEnabled': value.ambientBackgroundEnabled,
        'reduceMotion': value.reduceMotion,
        'reduceFlashing': value.reduceFlashing,
        'highContrast': value.highContrast,
        'ambientMotionMode': value.ambientMotionMode.name,
        'photographyPreferences': legacyPhotography,
        'activityPreferences': legacyActivities,
        'equipmentList': value.equipmentList,
        'aiTone': value.aiTone.name,
        'recommendationIntensity': value.recommendationIntensity,
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

  Set<String> _decodeStringSet(Object? value) {
    if (value is! List) return const <String>{};
    return value.whereType<String>().toSet();
  }

  AiTone _decodeAiTone(Object? value) {
    if (value is! String) return AiTone.balanced;
    return AiTone.values.firstWhere(
      (tone) => tone.name == value,
      orElse: () => AiTone.balanced,
    );
  }
}

class DriftProfilePreferencesStore implements ProfilePreferencesStore {
  DriftProfilePreferencesStore(this._database, this._preferences);

  final AppDatabase _database;
  final SharedPreferencesAsync _preferences;

  @override
  Future<ProfilePreferences?> read() async {
    final row = await _database
        .select(_database.profilePreferenceRecords)
        .getSingleOrNull();
    if (row != null) return _decodeRow(row);

    final legacyStore = SharedPreferencesProfilePreferencesStore(_preferences);
    final legacy = await legacyStore.read();
    if (legacy == null) return null;

    await write(legacy);
    await _preferences.remove(SharedPreferencesProfilePreferencesStore._key);
    return legacy;
  }

  @override
  Future<void> write(ProfilePreferences value) {
    final photography = value.photographyPreferences.toList()..sort();
    final activities = value.activityPreferences.toList()..sort();
    return _database.transaction(() async {
      await _database
          .into(_database.profilePreferenceRecords)
          .insertOnConflictUpdate(
            ProfilePreferenceRecordsCompanion.insert(
              id: const Value(1),
              ambientBackgroundEnabled: value.ambientBackgroundEnabled,
              reduceMotion: value.reduceMotion,
              reduceFlashing: value.reduceFlashing,
              highContrast: value.highContrast,
              ambientMotionMode: value.ambientMotionMode.name,
              photographyPreferencesJson: jsonEncode(photography),
              activityPreferencesJson: jsonEncode(activities),
              equipmentList: value.equipmentList,
              aiTone: value.aiTone.name,
              recommendationIntensity: value.recommendationIntensity,
            ),
          );
    });
  }

  ProfilePreferences _decodeRow(ProfilePreferenceRow row) {
    return ProfilePreferences(
      ambientBackgroundEnabled: row.ambientBackgroundEnabled,
      reduceMotion: row.reduceMotion,
      reduceFlashing: row.reduceFlashing,
      highContrast: row.highContrast,
      ambientMotionMode: AmbientMotionMode.values.byName(row.ambientMotionMode),
      photographyPreferences: _decodeSet(row.photographyPreferencesJson),
      activityPreferences: _decodeSet(row.activityPreferencesJson),
      equipmentList: row.equipmentList,
      aiTone: AiTone.values.byName(row.aiTone),
      recommendationIntensity: row.recommendationIntensity,
    );
  }

  Set<String> _decodeSet(String raw) {
    final value = jsonDecode(raw);
    if (value is! List) return const <String>{};
    return value.whereType<String>().toSet();
  }
}

final profilePreferencesStoreProvider = Provider<ProfilePreferencesStore>((
  ref,
) {
  return DriftProfilePreferencesStore(
    ref.watch(appDatabaseProvider),
    SharedPreferencesAsync(),
  );
});
