import 'package:luma_nest/src/core/context/context_snapshot.dart';

enum WeatherCondition { clear, cloudy, rain, snow, dust, thunder, unknown }

class WeatherObservation {
  const WeatherObservation({
    required this.observedAt,
    required this.temperatureCelsius,
    required this.condition,
    required this.windSpeedMetersPerSecond,
    required this.windDirectionDegrees,
    required this.visibilityKilometers,
    required this.precipitationMillimeters,
    this.cloudCoverPercent,
    this.windGustMetersPerSecond,
  });

  final DateTime observedAt;
  final double temperatureCelsius;
  final WeatherCondition condition;
  final double windSpeedMetersPerSecond;
  final double windDirectionDegrees;
  final double visibilityKilometers;
  final double precipitationMillimeters;
  final double? cloudCoverPercent;
  final double? windGustMetersPerSecond;

  bool get hasThunder => condition == WeatherCondition.thunder;

  WeatherType get contextWeatherType => switch (condition) {
    WeatherCondition.clear => WeatherType.clear,
    WeatherCondition.cloudy => WeatherType.cloudy,
    WeatherCondition.rain || WeatherCondition.thunder => WeatherType.rain,
    WeatherCondition.snow => WeatherType.snow,
    WeatherCondition.dust => WeatherType.dust,
    WeatherCondition.unknown => WeatherType.cloudy,
  };
}
