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
      creativeIds: const ['blue-hour', 'reflection', 'humanity-light'],
    );

    List<String> ordered(double intensity) => ManifestPolicy.build(
      snapshot,
      now: now,
      personalization: CreativePersonalization(
        photographyPreferences: const {PhotographyPreference.humanities},
        recommendationIntensity: intensity,
      ),
    ).creativeItems.map((item) => item.id).toList();

    expect(ordered(0.3), ['blue-hour', 'reflection', 'humanity-light']);
    expect(ordered(0.5), ['blue-hour', 'humanity-light', 'reflection']);
    expect(ordered(0.8), ['humanity-light', 'blue-hour', 'reflection']);
  });

  test(
    'personalized primary keeps summary and inspiration preview coherent',
    () {
      final manifest = ManifestPolicy.build(
        _serverSnapshot(
          now,
          creativeIds: const ['reflection', 'humanity-light'],
        ),
        now: now,
        personalization: CreativePersonalization(
          photographyPreferences: const {PhotographyPreference.humanities},
          recommendationIntensity: 1,
        ),
      );

      expect(manifest.primary?.id, 'humanity-light');
      expect(manifest.summary, '晨昏光线正在进入街巷，适合先观察再拍摄。');
      expect(manifest.inspirationPreview, '进巷子🏮');
    },
  );

  test(
    'astro and unknown events neither reorder nor invent creative events',
    () {
      final snapshot = _localSnapshot(
        now,
        opportunityIds: const ['unknown-event', 'reflection'],
      );
      final manifest = ManifestPolicy.build(
        snapshot,
        now: now,
        personalization: CreativePersonalization(
          photographyPreferences: const {PhotographyPreference.astro},
          recommendationIntensity: 1,
        ),
      );

      expect(manifest.creativeItems.map((item) => item.id), ['reflection']);
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
      allowedAction: ContextAction.openSafety,
    );
    final snapshot = ContextSnapshot(
      id: 'safety-personalization',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.blueHour,
      weather: WeatherType.rain,
      activeRoute: false,
      opportunityIds: const ['blue-hour', 'humanity-light'],
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
