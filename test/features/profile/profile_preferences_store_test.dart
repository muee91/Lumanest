import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/profile/infrastructure/profile_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storageKey = 'profile_preferences_v1';
  late AppDatabase database;
  late SharedPreferencesAsync preferences;
  late DriftProfilePreferencesStore store;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    preferences = SharedPreferencesAsync();
    await preferences.clear();
    store = DriftProfilePreferencesStore(database, preferences);
  });

  tearDown(() => database.close());

  test('drift round-trips every profile preference', () async {
    const value = ProfilePreferences(
      ambientBackgroundEnabled: false,
      reduceMotion: true,
      reduceFlashing: true,
      highContrast: true,
      ambientMotionMode: AmbientMotionMode.staticColor,
      photographyPreferences: {'星空', '风光'},
      activityPreferences: {'自驾', '轻徒步'},
      equipmentList: '相机、三脚架',
      aiTone: AiTone.detailed,
      recommendationIntensity: 0.8,
    );

    await store.write(value);

    expect(await store.read(), value);
    final row = await database
        .select(database.profilePreferenceRecords)
        .getSingle();
    expect(row.photographyPreferencesJson, '["星空","风光"]');
    expect(row.activityPreferencesJson, '["自驾","轻徒步"]');
  });

  test('a later write replaces the singleton preference row', () async {
    await store.write(const ProfilePreferences(photographyPreferences: {'风光'}));
    const replacement = ProfilePreferences(
      photographyPreferences: {'人文'},
      aiTone: AiTone.concise,
      recommendationIntensity: 0.2,
    );

    await store.write(replacement);

    expect(await store.read(), replacement);
    expect(
      await database.select(database.profilePreferenceRecords).get(),
      hasLength(1),
    );
  });

  test('imports legacy preferences and removes the key after commit', () async {
    await preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'ambientBackgroundEnabled': true,
        'reduceMotion': false,
        'reduceFlashing': false,
        'highContrast': true,
        'ambientMotionMode': 'energySaver',
        'photographyPreferences': ['人文'],
        'activityPreferences': ['自驾'],
        'equipmentList': '35mm',
        'aiTone': 'concise',
        'recommendationIntensity': 0.3,
      }),
    );

    final imported = await store.read();

    expect(imported?.ambientMotionMode, AmbientMotionMode.energySaver);
    expect(imported?.photographyPreferences, {'人文'});
    expect(imported?.aiTone, AiTone.concise);
    expect(await preferences.getString(storageKey), isNull);
    expect((await store.read())?.equipmentList, '35mm');
  });

  test('old version-one data without a mode defaults to full', () async {
    await preferences.setString(
      storageKey,
      jsonEncode({
        'version': 1,
        'ambientBackgroundEnabled': true,
        'reduceMotion': false,
        'reduceFlashing': false,
      }),
    );

    expect((await store.read())?.ambientMotionMode, AmbientMotionMode.full);
  });

  test('malformed legacy JSON is ignored and retained', () async {
    await preferences.setString(storageKey, '{not-json');

    expect(await store.read(), isNull);
    expect(await preferences.getString(storageKey), '{not-json');
  });

  test('failed legacy import rolls back and retains the source', () async {
    final raw = jsonEncode({
      'version': 1,
      'ambientBackgroundEnabled': true,
      'reduceMotion': false,
      'reduceFlashing': false,
      'recommendationIntensity': 2,
    });
    await preferences.setString(storageKey, raw);

    await expectLater(store.read(), throwsA(anything));

    expect(await preferences.getString(storageKey), raw);
    expect(
      await database.select(database.profilePreferenceRecords).get(),
      isEmpty,
    );
  });
}
