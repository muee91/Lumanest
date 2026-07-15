import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
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

  test('lake sunset prioritizes reflection and limits secondary cards', () {
    final manifest = ManifestPolicy.build(ContextFixtures.lakeSunset());

    expect(manifest.layoutMode, LayoutMode.opportunity);
    expect(manifest.primary?.id, 'reflection');
    expect(manifest.secondary, hasLength(1));
    expect(manifest.secondary.length, lessThanOrEqualTo(2));
  });

  test('mountain dawn emits alpenglow only when present in context', () {
    final withAlpenglow = ManifestPolicy.build(ContextFixtures.mountainDawn());
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

    expect(withAlpenglow.primary?.id, 'alpenglow');
    expect(withoutAlpenglow.primary, isNull);
  });

  test('safety events are separate from creative cards (structured event)', () {
    final now = DateTime.utc(2026, 7, 11, 10);
    final manifest = ManifestPolicy.build(
      ContextSnapshot(
        id: 'storm-safety',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        opportunityIds: const ['mist'],
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
            allowedAction: ContextAction.openSafety,
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
          primaryScene: SceneType.hiking,
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
              allowedAction: ContextAction.openSafety,
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
      opportunityIds: const ['blue-hour', 'reflection'],
      events: [
        ContextEvent(
          id: 'blue-hour',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.solar,
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 10)),
          confidence: .9,
        ),
        ContextEvent(
          id: 'reflection',
          channel: ContextEventChannel.opportunity,
          source: ContextEventSource.rule,
          observedAt: now.subtract(const Duration(hours: 1)),
          expiresAt: now.subtract(const Duration(minutes: 1)),
          confidence: .8,
        ),
      ],
    );

    final manifest = ManifestPolicy.build(snapshot, now: now);

    expect(manifest.primary?.id, 'blue-hour');
    expect(manifest.primary?.source, ContextEventSource.solar);
    expect(manifest.primary?.confidence, .9);
    expect(
      manifest.secondary.map((item) => item.id),
      isNot(contains('reflection')),
    );
  });

  test('no serverManifest old creative fallback does not regress', () {
    final manifest = ManifestPolicy.build(ContextFixtures.lakeSunset());

    // Local fallback still works without a server manifest: known opportunity
    // IDs produce creative items even without structured events.
    expect(manifest.layoutMode, LayoutMode.opportunity);
    expect(manifest.primary?.id, 'reflection');
    expect(manifest.secondary.first.id, 'blue-hour');
  });

  // ---------------------------------------------------------------------------
  // Server manifest tests
  // ---------------------------------------------------------------------------

  group('server manifest', () {
    final now = DateTime.utc(2026, 7, 15, 10);

    ContextEvent opportunityEvent({
      required String id,
      ContextAction? action,
    }) => ContextEvent(
      id: id,
      channel: ContextEventChannel.opportunity,
      source: ContextEventSource.solar,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
      confidence: 0.8,
      allowedAction: action,
    );

    ContextEvent safetyEvent({
      required String id,
      ContextEventSource source = ContextEventSource.weather,
      ContextAction? action,
      DateTime? expiresAt,
    }) => ContextEvent(
      id: id,
      channel: ContextEventChannel.safety,
      source: source,
      observedAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(minutes: 30)),
      confidence: 0.85,
      safetyLevel: ContextSafetyLevel.warning,
      allowedAction: action ?? ContextAction.openSafety,
    );

    ContextEvent wildlifeSafetyEvent({
      required String id,
      ContextAction? action,
    }) => ContextEvent(
      id: id,
      channel: ContextEventChannel.wildlifeSafety,
      source: ContextEventSource.wildlifeHistorical,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
      confidence: 0.7,
      allowedAction: action ?? ContextAction.openSafety,
    );

    test('server layout and creative order follow manifest', () {
      final snapshot = ContextSnapshot(
        id: 'server-creative',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.lake,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.cloudy,
        activeRoute: false,
        events: [
          opportunityEvent(id: 'reflection'),
          opportunityEvent(id: 'blue-hour'),
          opportunityEvent(id: 'mist'),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.opportunity,
          primaryEventId: 'mist',
          secondaryEventIds: const ['reflection', 'blue-hour'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.layoutMode, LayoutMode.opportunity);
      expect(manifest.primary?.id, 'mist');
      expect(manifest.secondary.map((item) => item.id), [
        'reflection',
        'blue-hour',
      ]);
    });

    test('server safety layout maps to operation', () {
      final snapshot = ContextSnapshot(
        id: 'server-safety-layout',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: false,
        events: [safetyEvent(id: 'thunderstorm')],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.safety,
          safetyEventIds: const ['thunderstorm'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.layoutMode, LayoutMode.operation);
      expect(manifest.safety.map((item) => item.id), contains('thunderstorm'));
    });

    test('missing structured safety in server list still shows', () {
      // Server manifest omits 'strong-wind' from safetyEventIds, but it exists
      // as a current unexpired structured safety event — must still appear.
      final snapshot = ContextSnapshot(
        id: 'server-missing-safety',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.mountain,
        dayPhase: DayPhase.day,
        weather: WeatherType.dust,
        activeRoute: false,
        events: [
          safetyEvent(id: 'thunderstorm'),
          safetyEvent(id: 'strong-wind'),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.safety,
          safetyEventIds: const ['thunderstorm'], // omits strong-wind
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(
        manifest.safety.map((item) => item.id),
        containsAll(['thunderstorm', 'strong-wind']),
      );
    });

    test('unknown official safety event gets generic title', () {
      final snapshot = ContextSnapshot(
        id: 'server-unknown-official-safety',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: false,
        events: [
          safetyEvent(
            id: 'official-landslide-alert',
            source: ContextEventSource.official,
          ),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.safety,
          safetyEventIds: const ['official-landslide-alert'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      final item = manifest.safety.firstWhere(
        (item) => item.id == 'official-landslide-alert',
      );
      expect(item.title, '官方安全预警');
    });

    test('reviewed astronomy event keeps catalog title and authority URL', () {
      final authority = Uri.parse('https://science.nasa.gov/meteor-showers/');
      final snapshot = ContextSnapshot(
        id: 'server-astronomy',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.unknown,
        dayPhase: DayPhase.night,
        weather: WeatherType.clear,
        activeRoute: false,
        events: [
          ContextEvent(
            id: 'astronomy-123456789abc',
            channel: ContextEventChannel.opportunity,
            source: ContextEventSource.astronomyCatalog,
            observedAt: now.subtract(const Duration(hours: 1)),
            expiresAt: now.add(const Duration(hours: 2)),
            confidence: 1,
            geoScope: ContextGeoScope.regional,
            safetyLevel: ContextSafetyLevel.info,
            allowedAction: ContextAction.openAuthority,
            title: '英仙座流星雨极大期',
            sourceUri: authority,
          ),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.opportunity,
          primaryEventId: 'astronomy-123456789abc',
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.primary?.title, '英仙座流星雨极大期');
      expect(manifest.primary?.action, ManifestAction.openAuthority);
      expect(manifest.primary?.authorityUri, authority);
      expect(manifest.summary, contains('实际可见性'));
      expect(manifest.inspirationPreview, '看天象✨');
    });

    test('unknown non-official safety event gets generic title', () {
      final snapshot = ContextSnapshot(
        id: 'server-unknown-env-safety',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: false,
        events: [
          safetyEvent(
            id: 'custom-flood-alert',
            source: ContextEventSource.rule,
          ),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.safety,
          safetyEventIds: const ['custom-flood-alert'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      final item = manifest.safety.firstWhere(
        (item) => item.id == 'custom-flood-alert',
      );
      expect(item.title, '环境安全提醒');
    });

    test('event openRoute action is preserved for hiking-return-check', () {
      final snapshot = ContextSnapshot(
        id: 'server-openroute-action',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.cloudy,
        activeRoute: true,
        events: [
          ContextEvent(
            id: 'hiking-return-check',
            channel: ContextEventChannel.safety,
            source: ContextEventSource.rule,
            observedAt: now,
            expiresAt: now.add(const Duration(minutes: 30)),
            confidence: 0.8,
            safetyLevel: ContextSafetyLevel.caution,
            allowedAction: ContextAction
                .openRoute, // structured event says openRoute, not openSafety
          ),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.safety,
          safetyEventIds: const ['hiking-return-check'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      final item = manifest.safety.firstWhere(
        (item) => item.id == 'hiking-return-check',
      );
      // Template says openSafety but the structured event's allowedAction
      // (openRoute) must win.
      expect(item.action, ManifestAction.openRoute);
    });

    test('expired server event is not shown', () {
      final snapshot = ContextSnapshot(
        id: 'server-expired-event',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.lake,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.cloudy,
        activeRoute: false,
        events: [
          opportunityEvent(id: 'reflection'),
          // 'blue-hour' is expired
          ContextEvent(
            id: 'blue-hour',
            channel: ContextEventChannel.opportunity,
            source: ContextEventSource.solar,
            observedAt: now.subtract(const Duration(hours: 2)),
            expiresAt: now.subtract(const Duration(minutes: 1)),
            confidence: 0.9,
          ),
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.opportunity,
          primaryEventId: 'blue-hour', // expired — must not appear
          secondaryEventIds: const ['reflection'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      // Expired primary (blue-hour) is dropped; reflection becomes primary.
      expect(manifest.primary?.id, 'reflection');
      expect(
        manifest.creativeItems.map((item) => item.id),
        isNot(contains('blue-hour')),
      );
    });

    test('bare bear-risk without structured event does not show', () {
      // No server manifest, no structured event — bare wildlifeEventIds must
      // not produce a safety entry.
      final snapshot = ContextSnapshot(
        id: 'bare-bear-risk',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.dawn,
        weather: WeatherType.clear,
        activeRoute: true,
        wildlifeEventIds: const ['bear-risk'], // no structured event
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.safety, isEmpty);
    });

    test('structured unexpired wildlifeSafety bear-risk shows', () {
      final snapshot = ContextSnapshot(
        id: 'structured-bear-risk',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.dawn,
        weather: WeatherType.clear,
        activeRoute: true,
        events: [wildlifeSafetyEvent(id: 'bear-risk')],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.safety,
          safetyEventIds: const ['bear-risk'],
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.safety.map((item) => item.id), contains('bear-risk'));
    });

    test('server creative without current event is dropped', () {
      final snapshot = ContextSnapshot(
        id: 'server-creative-no-event',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.lake,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.cloudy,
        activeRoute: false,
        events: [
          opportunityEvent(id: 'reflection'),
          // 'mist' is referenced by server manifest but has no structured event
        ],
        serverManifest: ServerManifest(
          layout: ServerManifestLayout.opportunity,
          primaryEventId: 'reflection',
          secondaryEventIds: const ['mist'], // no event — must not appear
        ),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.primary?.id, 'reflection');
      expect(manifest.secondary, isEmpty);
    });

    test('server quiet layout with no events', () {
      final snapshot = ContextSnapshot(
        id: 'server-quiet',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        events: const [],
        serverManifest: ServerManifest(layout: ServerManifestLayout.quiet),
      );

      final manifest = ManifestPolicy.build(snapshot, now: now);

      expect(manifest.layoutMode, LayoutMode.quiet);
      expect(manifest.primary, isNull);
      expect(manifest.secondary, isEmpty);
      expect(manifest.safety, isEmpty);
    });
  });
}
