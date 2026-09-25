import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Local fallback tests (no server manifest)
  // ---------------------------------------------------------------------------

  test('quiet city emits no dynamic opportunity placeholders', () {
    final manifest = ManifestPolicy.build(ContextFixtures.quietCity());

    expect(manifest.layoutMode, LayoutMode.quiet);
    expect(manifest.summary, isNotEmpty);
    expect(manifest.primary, isNull);
    expect(manifest.secondary, isEmpty);
  });

  test('lake sunset prioritizes the water session', () {
    final snapshot = ContextFixtures.lakeSunset();
    final manifest = ManifestPolicy.build(snapshot, now: snapshot.observedAt);

    expect(manifest.layoutMode, LayoutMode.opportunity);
    expect(manifest.primary?.id, 'session.water.evening');
    expect(manifest.secondary, isEmpty);
    expect(manifest.secondary.length, lessThanOrEqualTo(2));
  });

  test('mountain dawn emits the Core session only when present', () {
    final mountainDawn = ContextFixtures.mountainDawn();
    final withAlpenglow = ManifestPolicy.build(
      mountainDawn,
      now: mountainDawn.observedAt,
    );
    final withoutAlpenglow = ManifestPolicy.build(
      ContextSnapshot(
        id: 'mountain-without-opportunity',
        observedAt: DateTime.utc(2026, 7, 11),
        expiresAt: DateTime.utc(2026, 7, 11, 0, 30),
        primaryScene: SceneType.mountain,
        dayPhase: DayPhase.dawn,
        weather: WeatherType.cloudy,
        activeRoute: false,
      ),
    );

    expect(withAlpenglow.primary?.id, 'session.mountain.morning');
    expect(withoutAlpenglow.primary, isNull);
  });

  test('safety events are separate from creative cards (structured event)', () {
    final now = DateTime.utc(2026, 7, 11, 10);
    final manifest = ManifestPolicy.build(
      ContextSnapshot(
        id: 'storm-safety',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        primaryScene: SceneType.mountain,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        opportunityIds: const ['event.atmosphere.morning_mist'],
        safetyEventIds: const ['thunderstorm'],
        events: [
          ContextEvent(
            id: 'thunderstorm',
            channel: ContextEventChannel.safety,
            source: ContextEventSource.weather,
            observedAt: now,
            expiresAt: now.add(const Duration(minutes: 10)),
            confidence: 0.9,
            safetyLevel: ContextSafetyLevel.warning,
            allowedAction: ContextAction.openSafetyDetail,
          ),
        ],
      ),
      now: now,
    );

    expect(manifest.safety.map((item) => item.id), contains('thunderstorm'));
    expect(
      manifest.creativeItems.map((item) => item.id),
      isNot(contains('thunderstorm')),
    );
    expect(manifest.inspirationPreview, isNot(contains('雷暴')));
  });

  test(
    'wildlife opportunities and risks enter separate channels (structured)',
    () {
      final now = DateTime.utc(2026, 7, 11, 10);
      final manifest = ManifestPolicy.build(
        ContextSnapshot(
          id: 'wildlife-context',
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 10)),
          primaryScene: SceneType.mountain,
          dayPhase: DayPhase.dawn,
          weather: WeatherType.clear,
          activeRoute: true,
          wildlifeEventIds: const ['regional-wildlife', 'bear-risk'],
          events: [
            ContextEvent(
              id: 'bear-risk',
              channel: ContextEventChannel.wildlifeSafety,
              source: ContextEventSource.wildlifeHistorical,
              observedAt: now,
              expiresAt: now.add(const Duration(minutes: 10)),
              confidence: 0.7,
              allowedAction: ContextAction.openSafetyDetail,
            ),
          ],
        ),
        now: now,
      );

      expect(
        manifest.creativeItems.map((item) => item.id),
        contains('regional-wildlife'),
      );
      expect(manifest.safety.map((item) => item.id), contains('bear-risk'));
      expect(
        manifest.creativeItems.map((item) => item.id),
        isNot(contains('bear-risk')),
      );
    },
  );

  test('manifest carries metadata and drops expired structured events', () {
    final now = DateTime.utc(2026, 7, 13, 10);
    final snapshot = ContextSnapshot(
      id: 'metadata',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.blueHour,
      weather: WeatherType.clear,
      activeRoute: false,
      opportunityIds: const ['session.city.blue_hour', 'session.water.evening'],
      events: [
        ContextEvent(
          id: 'session.city.blue_hour',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 10)),
          confidence: .9,
        ),
        ContextEvent(
          id: 'session.water.evening',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.rule,
          observedAt: now.subtract(const Duration(hours: 1)),
          expiresAt: now.subtract(const Duration(minutes: 1)),
          confidence: .8,
        ),
      ],
    );

    final manifest = ManifestPolicy.build(snapshot, now: now);

    expect(manifest.primary?.id, 'session.city.blue_hour');
    expect(manifest.primary?.source, ContextEventSource.solar);
    expect(manifest.primary?.confidence, .9);
    expect(
      manifest.secondary.map((item) => item.id),
      isNot(contains('session.water.evening')),
    );
  });

  test('current catalog fallback works without a server manifest', () {
    final now = DateTime.utc(2026, 7, 11, 10);
    final manifest = ManifestPolicy.build(
      ContextSnapshot(
        id: 'current-local-opportunities',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 20)),
        primaryScene: SceneType.lake,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.cloudy,
        activeRoute: false,
        opportunityIds: const [
          'session.water.evening',
          'session.city.blue_hour',
        ],
      ),
      now: now,
    );

    // Current catalog IDs can render locally without structured events.
    expect(manifest.layoutMode, LayoutMode.opportunity);
    expect(manifest.primary?.id, 'session.water.evening');
    expect(manifest.secondary.first.id, 'session.city.blue_hour');
  });

  // ---------------------------------------------------------------------------
  // Server manifest tests
  // ---------------------------------------------------------------------------

}
