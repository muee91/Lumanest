import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_rule_engine.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 10);

  WeatherObservation weather({
    WeatherCondition condition = WeatherCondition.clear,
    double wind = 2,
    double rain = 0,
    double visibility = 20,
  }) => WeatherObservation(
    observedAt: now,
    temperatureCelsius: 20,
    condition: condition,
    windSpeedMetersPerSecond: wind,
    windDirectionDegrees: 90,
    visibilityKilometers: visibility,
    precipitationMillimeters: rain,
  );

  SolarState solar(DayPhase phase) => SolarState(
    observedAt: now,
    elevationDegrees: 2,
    azimuthDegrees: 90,
    sunrise: now,
    sunset: now,
    dayPhase: phase,
  );

  test('creates the catalog water session with policy evidence expiry', () {
    final events = const ContextRuleEngine().evaluate(
      scene: SceneType.lake,
      weather: weather(),
      solar: solar(DayPhase.sunset),
      generatedAt: now,
    );

    final event = events.singleWhere(
      (event) => event.id == 'session.water.evening',
    );
    expect(event.channel, ContextEventChannel.opportunity);
    expect(event.source, ContextEventSource.rule);
    expect(event.confidence, greaterThan(0));
    expect(event.expiresAt.difference(now), const Duration(minutes: 20));
  });

  test('generates only active Core catalog opportunities', () {
    const engine = ContextRuleEngine();
    expect(
      engine
          .evaluate(
            scene: SceneType.city,
            weather: weather(),
            solar: solar(DayPhase.blueHour),
            generatedAt: now,
          )
          .map((e) => e.id),
      contains('session.city.blue_hour'),
    );
    expect(
      engine
          .evaluate(
            scene: SceneType.mountain,
            weather: weather(),
            solar: solar(DayPhase.dawn),
            generatedAt: now,
          )
          .map((e) => e.id),
      contains('session.mountain.morning'),
    );
    expect(
      engine
          .evaluate(
            scene: SceneType.desert,
            weather: weather(condition: WeatherCondition.dust),
            solar: solar(DayPhase.sunset),
            generatedAt: now,
          )
          .map((e) => e.id),
      contains('session.desert.side_light'),
    );
    expect(
      engine
          .evaluate(
            scene: SceneType.village,
            weather: weather(),
            solar: solar(DayPhase.dawn),
            generatedAt: now,
          )
          .map((e) => e.id),
      isEmpty,
    );
  });

  test('stale data cannot create high-confidence weather opportunities', () {
    final events = const ContextRuleEngine().evaluate(
      scene: SceneType.mountain,
      weather: weather(),
      solar: solar(DayPhase.dawn),
      generatedAt: now,
      isStale: true,
    );
    expect(
      events.where((event) => event.channel == ContextEventChannel.opportunity),
      isEmpty,
    );
  });

  test('safety events are independent from creative opportunities', () {
    final events = const ContextRuleEngine().evaluate(
      scene: SceneType.lake,
      weather: weather(condition: WeatherCondition.thunder, wind: 18, rain: 12),
      solar: solar(DayPhase.day),
      generatedAt: now,
    );
    expect(
      events
          .where((e) => e.channel == ContextEventChannel.safety)
          .map((e) => e.id),
      containsAll(['thunderstorm', 'strong-wind', 'heavy-rain']),
    );
    expect(
      events
          .where((e) => e.channel == ContextEventChannel.opportunity)
          .map((e) => e.id),
      isNot(contains('thunderstorm')),
    );
  });
}
