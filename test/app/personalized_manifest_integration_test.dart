import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/features/inspiration/presentation/inspiration_page.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/profile/infrastructure/profile_preferences_store.dart';
import 'package:luma_nest/src/features/today/presentation/today_page.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 12);
  late ContextSnapshot snapshot;

  setUp(() {
    snapshot = ContextSnapshot(
      id: 'shared-personalized-manifest',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.blueHour,
      weather: WeatherType.clear,
      activeRoute: false,
      events: [
        _opportunity(now, 'reflection'),
        _opportunity(now, 'humanity-light'),
      ],
      serverManifest: ServerManifest(
        layout: ServerManifestLayout.opportunity,
        primaryEventId: 'reflection',
        secondaryEventIds: ['humanity-light'],
      ),
    );
  });

  testWidgets('Today and Inspiration consume the same personalized primary', (
    tester,
  ) async {
    final store = _FixedProfileStore(
      const ProfilePreferences(
        photographyPreferences: {'人文'},
        recommendationIntensity: 1,
        reduceMotion: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profilePreferencesStoreProvider.overrideWithValue(store)],
        child: MaterialApp(home: LiveTodayPage(initialSnapshot: snapshot)),
      ),
    );
    await tester.pumpAndSettle();

    final primaryCard = find.byKey(const Key('primary-opportunity'));
    expect(
      find.descendant(of: primaryCard, matching: find.text('街巷光线正在变暖')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profilePreferencesStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: InspirationPage(snapshotAsync: AsyncData(snapshot)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('selected-inspiration-humanity-light')),
      findsOneWidget,
    );
  });
}

ContextEvent _opportunity(DateTime now, String id) => ContextEvent(
  id: id,
  channel: ContextEventChannel.opportunity,
  source: ContextEventSource.rule,
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 20)),
  confidence: 0.8,
);

class _FixedProfileStore implements ProfilePreferencesStore {
  _FixedProfileStore(this.value);

  ProfilePreferences value;

  @override
  Future<ProfilePreferences?> read() async => value;

  @override
  Future<void> write(ProfilePreferences value) async {
    this.value = value;
  }
}
