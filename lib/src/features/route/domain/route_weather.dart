import 'package:luma_nest/src/core/context/route_corridor_context.dart';

enum RouteWeatherCondition { clear, cloudy, rain, snow, dust, unknown }

enum RouteWeatherCoverage { full, partial }

enum RouteCorridorCoverage { full, partial, unavailable }

enum RouteCorridorReferenceStatus { reference, empty, noReference, unavailable }

enum RouteRestrictionStatus { present, noneObserved, unavailable }

enum RouteEvidenceStatus { verified, reference, unavailable }

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

class RouteCorridorSource {
  const RouteCorridorSource({
    required this.id,
    required this.title,
    required this.publisher,
    required this.url,
    this.license,
    this.version,
  });

  final String id;
  final String title;
  final String publisher;
  final String url;
  final String? license;
  final String? version;
}

class RouteCorridorFacilities {
  const RouteCorridorFacilities({
    required this.status,
    required this.parking,
    required this.fuel,
    required this.food,
    required this.water,
    required this.toilets,
    required this.shelter,
    required this.restArea,
  });

  final RouteCorridorReferenceStatus status;
  final int parking;
  final int fuel;
  final int food;
  final int water;
  final int toilets;
  final int shelter;
  final int restArea;

  int get supplyCount => fuel + food + water + toilets + shelter + restArea;
}

class RouteCorridorPhotography {
  const RouteCorridorPhotography({
    required this.status,
    required this.viewpointCount,
    required this.heritageCount,
  });

  final RouteCorridorReferenceStatus status;
  final int viewpointCount;
  final int heritageCount;
}

class RouteCorridorRestrictions {
  RouteCorridorRestrictions({
    required this.status,
    required Iterable<String> kinds,
    required this.authoritative,
    required Iterable<String> factIds,
  }) : kinds = List.unmodifiable(kinds),
       factIds = List.unmodifiable(factIds);

  final RouteRestrictionStatus status;
  final List<String> kinds;
  final bool authoritative;
  final List<String> factIds;
}

class RouteCorridorEvidence {
  RouteCorridorEvidence({
    required this.status,
    required Iterable<String> factIds,
  }) : factIds = List.unmodifiable(factIds);

  final RouteEvidenceStatus status;
  final List<String> factIds;
}

class RouteCorridorSegment {
  const RouteCorridorSegment({
    required this.progress,
    required this.expectedAt,
    required this.facilities,
    required this.photography,
    required this.restrictions,
    required this.evidence,
  });

  final double progress;
  final DateTime expectedAt;
  final RouteCorridorFacilities facilities;
  final RouteCorridorPhotography photography;
  final RouteCorridorRestrictions restrictions;
  final RouteCorridorEvidence evidence;
}

class RouteCorridorIntelligence {
  RouteCorridorIntelligence({
    required this.contractVersion,
    required this.generatedAt,
    required this.coverage,
    required this.requestedSegments,
    required this.availableSegments,
    required Iterable<RouteCorridorSource> sources,
    required Iterable<RouteCorridorSegment> segments,
    required Iterable<String> limitations,
  }) : sources = List.unmodifiable(sources),
       segments = List.unmodifiable(segments),
       limitations = List.unmodifiable(limitations);

  final int contractVersion;
  final DateTime generatedAt;
  final RouteCorridorCoverage coverage;
  final int requestedSegments;
  final int availableSegments;
  final List<RouteCorridorSource> sources;
  final List<RouteCorridorSegment> segments;
  final List<String> limitations;

  bool get hasAuthoritativeRestrictions => segments.any(
    (segment) =>
        segment.restrictions.status == RouteRestrictionStatus.present &&
        segment.restrictions.authoritative,
  );

  String get officialSourceLabel {
    for (final source in sources) {
      final value = '${source.id} ${source.title}'.toLowerCase();
      if (value.contains('official') || value.contains('notice')) {
        return source.publisher;
      }
    }
    return '官方公告';
  }
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
    this.corridor,
  }) : samples = List.unmodifiable(samples);

  final String routeId;
  final DateTime generatedAt;
  final String source;
  final RouteWeatherCoverage coverage;
  final int requestedSamples;
  final int availableSamples;
  final List<RouteWeatherSample> samples;
  final RouteCorridorIntelligence? corridor;

  bool get hasStaleSamples => samples.any((sample) => sample.stale);
}

abstract interface class RouteWeatherRepository {
  Future<RouteWeatherReport> fetch(RouteCorridorContext corridor);
}
