import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

void main() {
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

  test('safety events are separate from creative cards', () {
    final manifest = ManifestPolicy.build(
      ContextSnapshot(
        id: 'storm-safety',
        observedAt: DateTime.utc(2026, 7, 11),
        expiresAt: DateTime.utc(2026, 7, 11, 0, 10),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.day,
        weather: WeatherType.rain,
        activeRoute: true,
        opportunityIds: const ['mist'],
        safetyEventIds: const ['thunderstorm'],
      ),
    );

    expect(manifest.safety.map((item) => item.id), contains('thunderstorm'));
    expect(
      manifest.creativeItems.map((item) => item.id),
      isNot(contains('thunderstorm')),
    );
    expect(manifest.inspirationPreview, isNot(contains('雷暴')));
  });

  test('wildlife opportunities and risks enter separate channels', () {
    final manifest = ManifestPolicy.build(
      ContextSnapshot(
        id: 'wildlife-context',
        observedAt: DateTime.utc(2026, 7, 11),
        expiresAt: DateTime.utc(2026, 7, 11, 0, 10),
        primaryScene: SceneType.hiking,
        dayPhase: DayPhase.dawn,
        weather: WeatherType.clear,
        activeRoute: true,
        wildlifeEventIds: const ['regional-wildlife', 'bear-risk'],
      ),
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
  });
}
