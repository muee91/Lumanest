import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';

abstract interface class ProfilePreferencesStore {
  Future<ProfilePreferences?> read();
  Future<void> write(ProfilePreferences value);
}

class DriftProfilePreferencesStore implements ProfilePreferencesStore {
  DriftProfilePreferencesStore(this._database);

  final AppDatabase _database;

  @override
  Future<ProfilePreferences?> read() async => _database
      .select(_database.profilePreferenceRecords)
      .getSingleOrNull()
      .then((row) => row == null ? null : _decodeRow(row));

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

final profilePreferencesStoreProvider = Provider<ProfilePreferencesStore>(
  (ref) => DriftProfilePreferencesStore(ref.watch(appDatabaseProvider)),
);
