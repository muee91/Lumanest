import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/profile/infrastructure/profile_preferences_store.dart';

void main() {
  late AppDatabase database;
  late DriftProfilePreferencesStore store;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftProfilePreferencesStore(database);
  });

  tearDown(() => database.close());

  test('drift round-trips every current profile preference', () async {
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
      shareAnonymousPhotographyFeedback: true,
    );

    await store.write(value);

    expect(await store.read(), value);
    final row = await database
        .select(database.profilePreferenceRecords)
        .getSingle();
    expect(row.photographyPreferencesJson, '["星空","风光"]');
    expect(row.activityPreferencesJson, '["自驾","轻徒步"]');
    expect(row.shareAnonymousPhotographyFeedback, isTrue);
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
}
