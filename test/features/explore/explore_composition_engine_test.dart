import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/application/explore_composition_engine.dart';
import 'package:luma_nest/src/features/explore/domain/explore_composition.dart';

void main() {
  const engine = ExploreCompositionEngine();
  final now = DateTime.utc(2026, 7, 21, 12);

  test('an active warning never blocks Explore', () {
    final snapshot = ContextSnapshot(
      id: 'ctx_test',
      observedAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
      events: [
        ContextEvent(
          id: 'safety_1',
          channel: ContextEventChannel.safety,
          source: ContextEventSource.official,
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 30)),
          confidence: 1,
        ),
      ],
    );
    expect(
      engine.compose(snapshot: snapshot, brief: null).layoutMode,
      ExploreLayoutMode.mapFirst,
    );
  });

  test('without facts Explore falls back to map rather than a placeholder', () {
    expect(
      engine.compose(snapshot: null, brief: null).layoutMode,
      ExploreLayoutMode.mapFirst,
    );
  });
}
