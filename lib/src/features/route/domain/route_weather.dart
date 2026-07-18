import 'package:luma_nest/src/core/context/route_corridor_context.dart';

enum RouteWeatherCondition { clear, cloudy, rain, snow, dust, unknown }

enum RouteWeatherCoverage { full, partial }

class RouteWeatherSample {
  const RouteWeatherSample({
    required this.progress,
    required this.expectedAt,
    required this.forecastAt,
    required this.condition,
    required this.cloudCoverPercent,
    required this.windSpeedMps,
    required this.precipitationMm,
    required this.visibilityKm,
    required this.thunder,
    required this.stale,
  });

  final double progress;
  final DateTime expectedAt;
  final DateTime forecastAt;
  final RouteWeatherCondition condition;
  final double? cloudCoverPercent;
  final double windSpeedMps;
  final double precipitationMm;
  final double? visibilityKm;
  final bool thunder;
  final bool stale;
}

class RouteWeatherReport {
  RouteWeatherReport({
    required this.routeId,
    required this.generatedAt,
    required this.source,
    required this.coverage,
    required this.requestedSamples,
    required this.availableSamples,
    required Iterable<RouteWeatherSample> samples,
  }) : samples = List.unmodifiable(samples);

  final String routeId;
  final DateTime generatedAt;
  final String source;
  final RouteWeatherCoverage coverage;
  final int requestedSamples;
  final int availableSamples;
  final List<RouteWeatherSample> samples;

  bool get hasStaleSamples => samples.any((sample) => sample.stale);
}

abstract interface class RouteWeatherRepository {
  Future<RouteWeatherReport> fetch(RouteCorridorContext corridor);
}
