import 'package:qiguang/src/core/context/context_snapshot.dart';

abstract final class ContextFixtures {
  static final _baseTime = DateTime.utc(2026, 7, 11, 10);

  static ContextSnapshot quietCity() {
    return ContextSnapshot(
      id: 'fixture-city-quiet',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 30)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.clear,
      activeRoute: false,
    );
  }

  static ContextSnapshot lakeSunset() {
    return ContextSnapshot(
      id: 'fixture-lake-sunset',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 20)),
      primaryScene: SceneType.lake,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      activeRoute: false,
      opportunityIds: const ['reflection', 'blue-hour'],
    );
  }

  static ContextSnapshot mountainDawn() {
    return ContextSnapshot(
      id: 'fixture-mountain-dawn',
      observedAt: _baseTime,
      expiresAt: _baseTime.add(const Duration(minutes: 15)),
      primaryScene: SceneType.mountain,
      dayPhase: DayPhase.dawn,
      weather: WeatherType.clear,
      activeRoute: false,
      opportunityIds: const ['alpenglow'],
    );
  }
}
