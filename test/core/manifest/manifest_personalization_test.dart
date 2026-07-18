import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15, 12);

  test('low, medium and high intensity apply the approved stable ordering', () {
    final snapshot = _serverSnapshot(
      now,
      creativeIds: const [
        'event.sky.sunset_glow',
        'session.water.evening',
        'session.city.after_rain',
      ],
    );

    List<String> ordered(double intensity) => ManifestPolicy.build(
      snapshot,
      now: now,
      personalization: CreativePersonalization(
        photographyPreferences: const {PhotographyPreference.humanities},
        recommendationIntensity: intensity,
      ),
    ).creativeItems.map((item) => item.id).toList();

    expect(ordered(0.3), [
      'event.sky.sunset_glow',
      'session.water.evening',
      'session.city.after_rain',
    ]);
    expect(ordered(0.5), [
      'event.sky.sunset_glow',
      'session.city.after_rain',
      'session.water.evening',
    ]);
    expect(ordered(0.8), [
      'session.city.after_rain',
      'event.sky.sunset_glow',
      'session.water.evening',
    ]);
  });

  test(
    'personalized primary keeps summary and inspiration preview coherent',
    () {
      final manifest = ManifestPolicy.build(
        _serverSnapshot(
          now,
          creativeIds: const [
            'session.water.evening',
            'session.city.after_rain',
          ],
        ),
        now: now,
        personalization: CreativePersonalization(
          photographyPreferences: const {PhotographyPreference.humanities},
          recommendationIntensity: 1,
        ),
      );

      expect(manifest.primary?.id, 'session.city.after_rain');
      expect(manifest.summary, '降水正在减弱，湿地面和灯光可能形成反光。');
      expect(manifest.inspirationPreview, '雨后有光🌧️');
    },
  );

  test(
    'astro and unknown events neither reorder nor invent creative events',
    () {
      final snapshot = _localSnapshot(
        now,
        opportunityIds: const ['unknown-event', 'session.water.evening'],
      );
      final manifest = ManifestPolicy.build(
        snapshot,
        now: now,
        personalization: CreativePersonalization(
          photographyPreferences: const {PhotographyPreference.astro},
          recommendationIntensity: 1,
        ),
      );

      expect(manifest.creativeItems.map((item) => item.id), [
        'session.water.evening',
      ]);
    },
  );

  test('personalization never changes safety items or their metadata', () {
    final safety = ContextEvent(
      id: 'thunderstorm',
      channel: ContextEventChannel.safety,
      source: ContextEventSource.official,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      confidence: 0.95,
      safetyLevel: ContextSafetyLevel.critical,
      allowedAction: ContextAction.openSafetyDetail,
    );
    final snapshot = ContextSnapshot(
      id: 'safety-personalization',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.blueHour,
      weather: WeatherType.rain,
      activeRoute: false,
      opportunityIds: const [
        'session.city.blue_hour',
        'session.city.after_rain',
      ],
      safetyEventIds: const ['thunderstorm'],
      events: [safety],
    );

    final original = ManifestPolicy.build(snapshot, now: now).safety.single;
    final personalized = ManifestPolicy.build(
      snapshot,
      now: now,
      personalization: CreativePersonalization(
        photographyPreferences: const {PhotographyPreference.humanities},
        recommendationIntensity: 1,
      ),
    ).safety.single;

    expect(personalized.id, original.id);
    expect(personalized.action, original.action);
    expect(personalized.source, original.source);
    expect(personalized.confidence, original.confidence);
    expect(personalized.expiresAt, original.expiresAt);
  });
}

ContextSnapshot _serverSnapshot(
  DateTime now, {
  required List<String> creativeIds,
}) {
  return ContextSnapshot(
    id: 'personalized-server',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 20)),
    primaryScene: SceneType.city,
    dayPhase: DayPhase.blueHour,
    weather: WeatherType.clear,
    activeRoute: false,
    events: [for (final id in creativeIds) _opportunity(now, id)],
    serverManifest: ServerManifest(
      layout: ServerManifestLayout.opportunity,
      primaryEventId: creativeIds.first,
      secondaryEventIds: creativeIds.skip(1).toList(),
    ),
  );
}

ContextSnapshot _localSnapshot(
  DateTime now, {
  required List<String> opportunityIds,
}) {
  return ContextSnapshot(
    id: 'personalized-local',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 20)),
    primaryScene: SceneType.lake,
    dayPhase: DayPhase.sunset,
    weather: WeatherType.clear,
    activeRoute: false,
    opportunityIds: opportunityIds,
  );
}

ContextEvent _opportunity(DateTime now, String id) => ContextEvent(
  id: id,
  channel: ContextEventChannel.opportunity,
  source: ContextEventSource.rule,
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 20)),
  confidence: 0.8,
);
