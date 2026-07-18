import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/photography/next_photography_window.dart';

void main() {
  test(
    'clear fresh night becomes a generic night-sky window, not Milky Way',
    () {
      final now = DateTime.utc(2026, 7, 18, 14, 37);
      final result = NextPhotographyWindowResolver.resolve(
        snapshot: _snapshot(now, cloud: 18, visibility: 16, precipitation: 0),
        now: now,
        nextSunrise: now.add(const Duration(hours: 6)),
      );

      expect(result?.kind, NextPhotographyWindowKind.nightSky);
      expect(result?.title, contains('夜空'));
      expect(result?.title, isNot(contains('银河')));
      expect(result?.action, NextPhotographyWindowAction.exploreNightSky);
    },
  );

  test('poor night conditions bridge to the next reachable sunrise', () {
    final now = DateTime.utc(2026, 7, 18, 14, 37);
    final sunrise = now.add(const Duration(hours: 6, minutes: 34));
    final result = NextPhotographyWindowResolver.resolve(
      snapshot: _snapshot(now, cloud: 82, visibility: 7, precipitation: 0),
      now: now,
      nextSunrise: sunrise,
    );

    expect(result?.kind, NextPhotographyWindowKind.sunriseReference);
    expect(result?.judgement, contains('下一次光线变化'));
    expect(result?.action, NextPhotographyWindowAction.exploreSunrise);
  });

  test('stale data never creates an actionable night bridge', () {
    final now = DateTime.utc(2026, 7, 18, 14, 37);
    final result = NextPhotographyWindowResolver.resolve(
      snapshot: _snapshot(
        now,
        cloud: 10,
        visibility: 20,
        precipitation: 0,
        stale: true,
      ),
      now: now,
      nextSunrise: now.add(const Duration(hours: 6)),
    );

    expect(result, isNull);
  });
}

ContextSnapshot _snapshot(
  DateTime now, {
  required double cloud,
  required double visibility,
  required double precipitation,
  bool stale = false,
}) => ContextSnapshot(
  id: 'night-test',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 20)),
  primaryScene: SceneType.village,
  dayPhase: DayPhase.night,
  weather: WeatherType.clear,
  activeRoute: false,
  cloudCoverPercent: cloud,
  visibilityKilometers: visibility,
  precipitationMillimeters: precipitation,
  windSpeedMetersPerSecond: 2,
  moonIllumination: .2,
  isStale: stale,
);
