import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/state/state_slice.dart';

enum EnvironmentSliceKey {
  location,
  weather,
  airQuality,
  solar,
  astronomy,
  scene,
  route,
  safety,
  opportunities,
  nearby,
  ambient,
}

class WeatherSliceValue {
  const WeatherSliceValue({
    required this.weather,
    this.temperatureCelsius,
    this.windSpeedMetersPerSecond,
    this.precipitationMillimeters,
    this.cloudCoverPercent,
    this.visibilityKilometers,
  });

  final WeatherType weather;
  final double? temperatureCelsius;
  final double? windSpeedMetersPerSecond;
  final double? precipitationMillimeters;
  final double? cloudCoverPercent;
  final double? visibilityKilometers;
}

class SolarSliceValue {
  const SolarSliceValue({
    this.elevationDegrees,
    this.azimuthDegrees,
    this.sunrise,
    this.sunset,
    required this.dayPhase,
  });

  final double? elevationDegrees;
  final double? azimuthDegrees;
  final DateTime? sunrise;
  final DateTime? sunset;
  final DayPhase dayPhase;
}

class EnvironmentState {
  const EnvironmentState({
    required this.snapshot,
    required this.entries,
    required this.slices,
    required this.revision,
  });

  final StateSlice<ContextSnapshot> snapshot;
  final StateSlice<List<ContextEntry>> entries;
  final Map<EnvironmentSliceKey, StateSlice<Object?>> slices;
  final int revision;

  StateSlice<Object?>? slice(EnvironmentSliceKey key) => slices[key];
}
