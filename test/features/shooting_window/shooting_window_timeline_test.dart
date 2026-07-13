import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/shooting_window/domain/shooting_window_timeline.dart';

void main() {
  test('builds ordered dawn, sunset and blue-hour reference windows', () {
    final sunrise = DateTime.utc(2026, 7, 13, 21);
    final sunset = DateTime.utc(2026, 7, 14, 11);
    final snapshot = ContextSnapshot(
      id: 'solar',
      observedAt: sunset.subtract(const Duration(minutes: 20)),
      expiresAt: sunset,
      primaryScene: SceneType.city,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.clear,
      activeRoute: false,
      sunrise: sunrise,
      sunset: sunset,
    );

    final windows = ShootingWindowTimeline.build(snapshot);

    expect(windows.map((window) => window.id), ['dawn', 'sunset', 'blue-hour']);
    expect(windows[1].isActiveAt(snapshot.observedAt), isTrue);
    expect(windows[2].start, sunset.add(const Duration(minutes: 20)));
  });

  test('returns no fabricated windows when solar events are unavailable', () {
    final snapshot = ContextSnapshot(
      id: 'polar',
      observedAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026, 1, 1, 1),
      primaryScene: SceneType.unknown,
      dayPhase: DayPhase.night,
      weather: WeatherType.clear,
      activeRoute: false,
    );
    expect(ShootingWindowTimeline.build(snapshot), isEmpty);
  });
}
