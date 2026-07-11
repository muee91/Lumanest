import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

void main() {
  test('clear weather maps to the context clear type', () {
    final observation = WeatherObservation(
      observedAt: DateTime.utc(2026, 7, 11),
      temperatureCelsius: 26,
      condition: WeatherCondition.clear,
      windSpeedMetersPerSecond: 2,
      windDirectionDegrees: 180,
      visibilityKilometers: 20,
      precipitationMillimeters: 0,
    );

    expect(observation.contextWeatherType, WeatherType.clear);
  });

  test('thunder condition maps to rain while preserving thunder flag', () {
    final observation = WeatherObservation(
      observedAt: DateTime.utc(2026, 7, 11),
      temperatureCelsius: 22,
      condition: WeatherCondition.thunder,
      windSpeedMetersPerSecond: 8,
      windDirectionDegrees: 270,
      visibilityKilometers: 5,
      precipitationMillimeters: 12,
    );

    expect(observation.contextWeatherType, WeatherType.rain);
    expect(observation.hasThunder, isTrue);
  });

  test('optional source fields remain absent when unavailable', () {
    final observation = WeatherObservation(
      observedAt: DateTime.utc(2026, 7, 11),
      temperatureCelsius: 20,
      condition: WeatherCondition.cloudy,
      windSpeedMetersPerSecond: 1,
      windDirectionDegrees: 90,
      visibilityKilometers: 10,
      precipitationMillimeters: 0,
    );

    expect(observation.cloudCoverPercent, isNull);
    expect(observation.windGustMetersPerSecond, isNull);
  });
}
