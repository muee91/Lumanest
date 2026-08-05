import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/route_corridor_context.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';

abstract interface class RouteWeatherTransport {
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  });
}

class DioRouteWeatherTransport implements RouteWeatherTransport {
  DioRouteWeatherTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  }) async {
    final response = await _dio.post<Object?>(
      url,
      data: body,
      options: Options(headers: headers),
    );
    if (response.data case final Map value) {
      return Map<String, Object?>.from(value);
    }
    throw const FormatException('Invalid route weather response');
  }
}

class DataBrokerRouteWeatherRepository implements RouteWeatherRepository {
  const DataBrokerRouteWeatherRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  static const _corridorKeys = {
    'contractVersion',
    'generatedAt',
    'coverage',
    'requestedSegments',
    'availableSegments',
    'sources',
    'segments',
    'limitations',
  };
  static const _sourceKeys = {
    'id',
    'title',
    'publisher',
    'url',
    'license',
    'version',
  };
  static const _segmentKeys = {
    'progress',
    'expectedAt',
    'facilities',
    'photography',
    'restrictions',
    'evidence',
  };
  static const _facilityKeys = {
    'status',
    'parking',
    'fuel',
    'food',
    'water',
    'toilets',
    'shelter',
    'restArea',
  };
  static const _photographyKeys = {
    'status',
    'viewpointCount',
    'heritageCount',
  };
  static const _restrictionKeys = {
    'status',
    'kinds',
    'authoritative',
    'factIds',
  };
  static const _evidenceKeys = {'status', 'factIds'};
  static const _restrictionKinds = {
    'closure',
    'roadClosure',
    'fireRestriction',
    'regulation',
    'eventChange',
  };
  static const _limitations = {
    'public_map_inventory_is_reference_only',
    'absence_of_official_notice_is_not_safety_confirmation',
    'precise_route_geometry_excluded',
  };

  final String brokerBaseUrl;
  final String serviceToken;
  final RouteWeatherTransport transport;

  @override
  Future<RouteWeatherReport> fetch(RouteCorridorContext corridor) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Route weather broker is not configured');
    }
    if (!corridor.isUsable ||
        corridor.samples.length < 2 ||
        corridor.samples.length > 5) {
      throw const FormatException('Route weather sample count is out of range');
    }
    final body = await transport.post(
      '$brokerBaseUrl/v1/route/weather',
      body: {
        'routeId': corridor.routeId,
        'samples': corridor.samples
            .map((sample) => sample.toRequest())
            .toList(growable: false),
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    return _parse(body, expectedRouteId: corridor.routeId);
  }

  RouteWeatherReport _parse(
    Map<String, Object?> body, {
    required String expectedRouteId,
  }) {
    final routeId = body['routeId'];
    final generatedAt = DateTime.tryParse(body['generatedAt'] as String? ?? '');
    final source = body['source'];
    final coverage = switch (body['coverage']) {
      'full' => RouteWeatherCoverage.full,
      'partial' => RouteWeatherCoverage.partial,
      _ => null,
    };
    final requestedSamples = body['requestedSamples'];
    final availableSamples = body['availableSamples'];
    final rawSamples = body['samples'];
    if (routeId != expectedRouteId ||
        generatedAt == null ||
        source is! String ||
        source.isEmpty ||
        coverage == null ||
        requestedSamples is! int ||
        requestedSamples < 2 ||
        requestedSamples > 5 ||
        availableSamples is! int ||
        availableSamples < 1 ||
        availableSamples > requestedSamples ||
        rawSamples is! List ||
        rawSamples.length != availableSamples) {
      throw const FormatException('Invalid route weather report');
    }
    final samples = <RouteWeatherSample>[];
    var previousProgress = -1.0;
    for (final raw in rawSamples) {
      if (raw is! Map) {
        throw const FormatException('Invalid route weather sample');
      }
      final sample = Map<String, Object?>.from(raw);
      final progress = (sample['progress'] as num?)?.toDouble();
      final expectedAt = DateTime.tryParse(
        sample['expectedAt'] as String? ?? '',
      );
      final forecastAt = DateTime.tryParse(
        sample['forecastAt'] as String? ?? '',
      );
      final condition = _condition(sample['condition']);
      final cloudCover = _nullableFinite(sample['cloudCoverPercent'], 0, 100);
      final windSpeed = _finite(sample['windSpeedMps'], 0, 150);
      final precipitation = _finite(sample['precipitationMm'], 0, 2000);
      final visibility = _nullableFinite(sample['visibilityKm'], 0, 500);
      final thunder = sample['thunder'];
      final stale = sample['stale'];
      if (progress == null ||
          !progress.isFinite ||
          progress < 0 ||
          progress > 1 ||
          progress <= previousProgress ||
          expectedAt == null ||
          forecastAt == null ||
          condition == null ||
          windSpeed == null ||
          precipitation == null ||
          thunder is! bool ||
          stale is! bool) {
        throw const FormatException('Invalid route weather sample');
      }
      samples.add(
        RouteWeatherSample(
          progress: progress,
          expectedAt: expectedAt,
          forecastAt: forecastAt,
          condition: condition,
          cloudCoverPercent: cloudCover,
          windSpeedMps: windSpeed,
          precipitationMm: precipitation,
          visibilityKm: visibility,
          thunder: thunder,
          stale: stale,
        ),
      );
      previousProgress = progress;
    }
    if (coverage == RouteWeatherCoverage.full &&
        availableSamples != requestedSamples) {
      throw const FormatException('Invalid route weather coverage');
    }
    return RouteWeatherReport(
      routeId: routeId as String,
      generatedAt: generatedAt,
      source: source,
      coverage: coverage,
      requestedSamples: requestedSamples,
      availableSamples: availableSamples,
      samples: samples,
      corridor: _parseCorridor(body['corridor']),
    );
  }

  RouteCorridorIntelligence? _parseCorridor(Object? raw) {
    if (raw == null) return null;
    final value = _map(raw, _corridorKeys, 'route corridor');
    final generatedAt = DateTime.tryParse(value['generatedAt'] as String? ?? '');
    final coverage = switch (value['coverage']) {
      'full' => RouteCorridorCoverage.full,
      'partial' => RouteCorridorCoverage.partial,
      'unavailable' => RouteCorridorCoverage.unavailable,
      _ => null,
    };
    final requested = _count(value['requestedSegments'], minimum: 2, maximum: 5);
    final available = _count(value['availableSegments'], maximum: requested ?? 0);
    final rawSources = value['sources'];
    final rawSegments = value['segments'];
    final rawLimitations = value['limitations'];
    if (value['contractVersion'] != 1 ||
        generatedAt == null ||
        coverage == null ||
        requested == null ||
        available == null ||
        rawSources is! List ||
        rawSources.length > 4 ||
        rawSegments is! List ||
        rawSegments.length != requested ||
        rawLimitations is! List ||
        rawLimitations.isEmpty ||
        rawLimitations.length > _limitations.length) {
      throw const FormatException('Invalid route corridor intelligence');
    }
    final limitations = _strings(
      rawLimitations,
      maximum: _limitations.length,
      allowed: _limitations,
    );
    final sources = rawSources.map(_parseSource).toList(growable: false);
    final segments = <RouteCorridorSegment>[];
    var previousProgress = -1.0;
    for (final item in rawSegments) {
      final segment = _parseSegment(item);
      if (segment.progress <= previousProgress) {
        throw const FormatException('Invalid route corridor segment order');
      }
      segments.add(segment);
      previousProgress = segment.progress;
    }
    if (coverage == RouteCorridorCoverage.full && available != requested ||
        coverage == RouteCorridorCoverage.unavailable && available != 0) {
      throw const FormatException('Invalid route corridor coverage');
    }
    return RouteCorridorIntelligence(
      contractVersion: 1,
      generatedAt: generatedAt,
      coverage: coverage,
      requestedSegments: requested,
      availableSegments: available,
      sources: sources,
      segments: segments,
      limitations: limitations,
    );
  }

  RouteCorridorSource _parseSource(Object? raw) {
    final value = _map(raw, _sourceKeys, 'route corridor source');
    final id = _text(value['id'], 120);
    final title = _text(value['title'], 160);
    final publisher = _text(value['publisher'], 160);
    final url = _text(value['url'], 500);
    final uri = url == null ? null : Uri.tryParse(url);
    final license = value['license'] == null ? null : _text(value['license'], 80);
    final version = value['version'] == null ? null : _text(value['version'], 120);
    if (id == null ||
        title == null ||
        publisher == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        value['license'] != null && license == null ||
        value['version'] != null && version == null) {
      throw const FormatException('Invalid route corridor source');
    }
    return RouteCorridorSource(
      id: id,
      title: title,
      publisher: publisher,
      url: uri.toString(),
      license: license,
      version: version,
    );
  }

  RouteCorridorSegment _parseSegment(Object? raw) {
    final value = _map(raw, _segmentKeys, 'route corridor segment');
    final progress = _finite(value['progress'], 0, 1);
    final expectedAt = DateTime.tryParse(value['expectedAt'] as String? ?? '');
    if (progress == null || expectedAt == null) {
      throw const FormatException('Invalid route corridor segment');
    }
    return RouteCorridorSegment(
      progress: progress,
      expectedAt: expectedAt,
      facilities: _parseFacilities(value['facilities']),
      photography: _parsePhotography(value['photography']),
      restrictions: _parseRestrictions(value['restrictions']),
      evidence: _parseEvidence(value['evidence']),
    );
  }

  RouteCorridorFacilities _parseFacilities(Object? raw) {
    final value = _map(raw, _facilityKeys, 'route corridor facilities');
    final status = switch (value['status']) {
      'reference' => RouteCorridorReferenceStatus.reference,
      'empty' => RouteCorridorReferenceStatus.empty,
      'unavailable' => RouteCorridorReferenceStatus.unavailable,
      _ => null,
    };
    final counts = [
      value['parking'],
      value['fuel'],
      value['food'],
      value['water'],
      value['toilets'],
      value['shelter'],
      value['restArea'],
    ].map((item) => _count(item, maximum: 1000)).toList(growable: false);
    if (status == null || counts.any((item) => item == null)) {
      throw const FormatException('Invalid route corridor facilities');
    }
    return RouteCorridorFacilities(
      status: status,
      parking: counts[0]!,
      fuel: counts[1]!,
      food: counts[2]!,
      water: counts[3]!,
      toilets: counts[4]!,
      shelter: counts[5]!,
      restArea: counts[6]!,
    );
  }

  RouteCorridorPhotography _parsePhotography(Object? raw) {
    final value = _map(raw, _photographyKeys, 'route corridor photography');
    final status = switch (value['status']) {
      'reference' => RouteCorridorReferenceStatus.reference,
      'noReference' => RouteCorridorReferenceStatus.noReference,
      'unavailable' => RouteCorridorReferenceStatus.unavailable,
      _ => null,
    };
    final viewpoint = _count(value['viewpointCount'], maximum: 1000);
    final heritage = _count(value['heritageCount'], maximum: 1000);
    if (status == null || viewpoint == null || heritage == null) {
      throw const FormatException('Invalid route corridor photography');
    }
    return RouteCorridorPhotography(
      status: status,
      viewpointCount: viewpoint,
      heritageCount: heritage,
    );
  }

  RouteCorridorRestrictions _parseRestrictions(Object? raw) {
    final value = _map(raw, _restrictionKeys, 'route restrictions');
    final status = switch (value['status']) {
      'present' => RouteRestrictionStatus.present,
      'noneObserved' => RouteRestrictionStatus.noneObserved,
      'unavailable' => RouteRestrictionStatus.unavailable,
      _ => null,
    };
    final kinds = _strings(value['kinds'], maximum: 4, allowed: _restrictionKinds);
    final factIds = _strings(value['factIds'], maximum: 4);
    final authoritative = value['authoritative'];
    if (status == null ||
        authoritative is! bool ||
        status == RouteRestrictionStatus.present &&
            (!authoritative || kinds.isEmpty || factIds.isEmpty) ||
        status != RouteRestrictionStatus.present &&
            (authoritative || kinds.isNotEmpty || factIds.isNotEmpty)) {
      throw const FormatException('Invalid route restrictions');
    }
    return RouteCorridorRestrictions(
      status: status,
      kinds: kinds,
      authoritative: authoritative,
      factIds: factIds,
    );
  }

  RouteCorridorEvidence _parseEvidence(Object? raw) {
    final value = _map(raw, _evidenceKeys, 'route corridor evidence');
    final status = switch (value['status']) {
      'verified' => RouteEvidenceStatus.verified,
      'reference' => RouteEvidenceStatus.reference,
      'unavailable' => RouteEvidenceStatus.unavailable,
      _ => null,
    };
    final factIds = _strings(value['factIds'], maximum: 5);
    if (status == null ||
        status == RouteEvidenceStatus.unavailable && factIds.isNotEmpty ||
        status != RouteEvidenceStatus.unavailable && factIds.isEmpty) {
      throw const FormatException('Invalid route corridor evidence');
    }
    return RouteCorridorEvidence(status: status, factIds: factIds);
  }

  Map<String, Object?> _map(
    Object? raw,
    Set<String> keys,
    String label,
  ) {
    if (raw is! Map) throw FormatException('Invalid $label');
    final value = Map<String, Object?>.from(raw);
    if (value.keys.any((key) => !keys.contains(key))) {
      throw FormatException('Invalid $label');
    }
    return value;
  }

  List<String> _strings(
    Object? raw, {
    required int maximum,
    Set<String>? allowed,
  }) {
    if (raw is! List || raw.length > maximum) {
      throw const FormatException('Invalid route corridor string list');
    }
    final result = <String>[];
    for (final item in raw) {
      final value = _text(item, 160);
      if (value == null ||
          allowed != null && !allowed.contains(value) ||
          result.contains(value)) {
        throw const FormatException('Invalid route corridor string list');
      }
      result.add(value);
    }
    return List.unmodifiable(result);
  }

  String? _text(Object? value, int maximum) {
    if (value is! String) return null;
    final result = value.trim();
    return result.isNotEmpty && result.length <= maximum ? result : null;
  }

  int? _count(Object? value, {int minimum = 0, required int maximum}) =>
      value is int && value >= minimum && value <= maximum ? value : null;

  RouteWeatherCondition? _condition(Object? value) => switch (value) {
    'clear' => RouteWeatherCondition.clear,
    'cloudy' => RouteWeatherCondition.cloudy,
    'rain' => RouteWeatherCondition.rain,
    'snow' => RouteWeatherCondition.snow,
    'dust' => RouteWeatherCondition.dust,
    'unknown' => RouteWeatherCondition.unknown,
    _ => null,
  };

  double? _finite(Object? value, double minimum, double maximum) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite && result >= minimum && result <= maximum
        ? result
        : null;
  }

  double? _nullableFinite(Object? value, double minimum, double maximum) =>
      value == null ? null : _finite(value, minimum, maximum);
}
