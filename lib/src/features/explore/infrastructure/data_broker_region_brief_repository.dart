import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief_repository.dart';

class RegionBriefFailure implements Exception {
  const RegionBriefFailure(this.code);

  final String code;
}

abstract interface class RegionBriefTransport {
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  });
}

class DioRegionBriefTransport implements RegionBriefTransport {
  DioRegionBriefTransport(this._dio);

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
    throw const RegionBriefFailure('invalid_response');
  }
}

class DataBrokerRegionBriefRepository implements RegionBriefRepository {
  const DataBrokerRegionBriefRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final RegionBriefTransport transport;

  @override
  Future<RegionBrief> fetch(RegionBriefRequest request) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const RegionBriefFailure('not_configured');
    }
    try {
      final raw = await transport.post(
        '$brokerBaseUrl/v1/explore/brief',
        body: {
          'contractVersion': 2,
          'snapshotId': request.snapshotId,
          'activationType': request.activationType,
          'locale': request.locale,
          'region': {
            'latitude': request.center.latitude,
            'longitude': request.center.longitude,
            'radiusMeters': request.radiusMeters.clamp(100, 50000),
          },
          'sceneProfile': request.sceneProfile.toJson(),
          'requestedSections': request.requestedSections,
        },
        headers: {
          'Authorization': 'Bearer $serviceToken',
          'Content-Type': 'application/json',
        },
      );
      return RegionBriefCodec.parse(raw);
    } on RegionBriefFailure {
      rethrow;
    } on Object {
      throw const RegionBriefFailure('unavailable');
    }
  }
}

abstract final class RegionBriefCodec {
  static RegionBrief parse(Map<String, Object?> raw) {
    if (!_exactKeys(raw, const {
          'contractVersion',
          'briefId',
          'regionId',
          'regionName',
          'profile',
          'generatedAt',
          'expiresAt',
          'status',
          'completeness',
          'identity',
          'orientation',
          'photoThemes',
          'insights',
          'sources',
          'refresh',
        }) ||
        raw['contractVersion'] != 2) {
      throw const RegionBriefFailure('invalid_contract');
    }
    final sources = _list(raw['sources']).map(_source).toList(growable: false);
    final sourceIds = sources.map((item) => item.id).toSet();
    final insights = _list(
      raw['insights'],
    ).map((item) => _insight(item, sourceIds)).toList(growable: false);
    final identity = _textBlockOrNull(raw['identity']);
    final orientation = _textBlockOrNull(raw['orientation']);
    final status = _enum(RegionBriefStatus.values, raw['status']);
    if (status == RegionBriefStatus.pending ||
        status == RegionBriefStatus.unavailable) {
      if (identity != null ||
          orientation != null ||
          sources.isNotEmpty ||
          insights.isNotEmpty) {
        throw const RegionBriefFailure('invalid_pending');
      }
    } else if (identity == null || orientation == null) {
      throw const RegionBriefFailure('missing_facts');
    }
    final factIds = insights.expand((item) => item.factIds).toSet();
    if ((identity?.factIds ?? const <String>[]).any(
          (id) => !factIds.contains(id),
        ) ||
        (orientation?.factIds ?? const <String>[]).any(
          (id) => !factIds.contains(id),
        )) {
      throw const RegionBriefFailure('unresolved_fact');
    }
    final refresh = _map(raw['refresh']);
    if (!_exactKeys(refresh, const {
      'refreshingMissions',
      'retryAfterSeconds',
    })) {
      throw const RegionBriefFailure('invalid_refresh');
    }
    final retrySeconds = refresh['retryAfterSeconds'];
    if (retrySeconds != null &&
        (retrySeconds is! int || retrySeconds < 1 || retrySeconds > 3600)) {
      throw const RegionBriefFailure('invalid_retry');
    }
    return RegionBrief(
      id: _id(raw['briefId']),
      regionId: _id(raw['regionId']),
      regionName: _string(raw['regionName'], maximum: 160),
      profile: _profile(_map(raw['profile'])),
      generatedAt: _date(raw['generatedAt']),
      expiresAt: _date(raw['expiresAt']),
      status: status,
      completeness: _enum(RegionBriefCompleteness.values, raw['completeness']),
      identity: identity,
      orientation: orientation,
      photoThemes: _list(
        raw['photoThemes'],
      ).map(_theme).toList(growable: false),
      insights: insights,
      sources: sources,
      refresh: RegionBriefRefresh(
        refreshingMissions: _list(
          refresh['refreshingMissions'],
        ).map((item) => _string(item, maximum: 64)).toList(growable: false),
        retryAfter: retrySeconds == null
            ? null
            : Duration(seconds: retrySeconds as int),
      ),
    );
  }

  static Map<String, Object?> encode(RegionBrief brief) => {
    'contractVersion': 2,
    'briefId': brief.id,
    'regionId': brief.regionId,
    'regionName': brief.regionName,
    'profile': brief.profile.toJson(),
    'generatedAt': brief.generatedAt.toUtc().toIso8601String(),
    'expiresAt': brief.expiresAt.toUtc().toIso8601String(),
    'status': brief.status.name,
    'completeness': brief.completeness.name,
    'identity': _encodeText(brief.identity),
    'orientation': _encodeText(brief.orientation),
    'photoThemes': brief.photoThemes
        .map((item) => {'id': item.id, 'label': item.label})
        .toList(growable: false),
    'insights': brief.insights.map(_encodeInsight).toList(growable: false),
    'sources': brief.sources.map(_encodeSource).toList(growable: false),
    'refresh': {
      'refreshingMissions': brief.refresh.refreshingMissions,
      'retryAfterSeconds': brief.refresh.retryAfter?.inSeconds,
    },
  };

  static Map<String, Object?>? _encodeText(FactBoundText? value) =>
      value == null
      ? null
      : {'summary': value.summary, 'factIds': value.factIds};

  static Map<String, Object?> _encodeSource(InsightEvidence value) => {
    'id': value.id,
    'sourcePolicyId': value.sourcePolicyId,
    'publisher': value.publisher,
    'title': value.title,
    'url': value.url.toString(),
    'observedAt': value.observedAt.toUtc().toIso8601String(),
    'qualityTier': switch (value.qualityTier) {
      InsightQualityTier.s => 'S',
      InsightQualityTier.a => 'A',
      InsightQualityTier.b => 'B',
      InsightQualityTier.c => 'C',
    },
    'publishedAt': value.publishedAt?.toUtc().toIso8601String(),
    'validFrom': value.validFrom?.toUtc().toIso8601String(),
    'validUntil': value.validUntil?.toUtc().toIso8601String(),
    'license': value.license,
    'version': value.version,
  };

  static Map<String, Object?> _encodeInsight(RegionInsight value) => {
    'id': value.id,
    'regionId': value.regionId,
    'type': value.type.name,
    'title': value.title,
    'summary': value.summary,
    'verification': value.verification.name,
    'factIds': value.factIds,
    'evidenceIds': value.evidenceIds,
    'observedAt': value.observedAt.toUtc().toIso8601String(),
    'expiresAt': value.expiresAt.toUtc().toIso8601String(),
    'placeId': value.placeId,
    'coordinate': value.point == null
        ? null
        : {
            'latitude': value.point!.latitude,
            'longitude': value.point!.longitude,
            'system': 'wgs84',
          },
    'startsAt': value.startsAt?.toUtc().toIso8601String(),
    'endsAt': value.endsAt?.toUtc().toIso8601String(),
    'timeSensitive': value.timeSensitive,
    'actionability': value.actionability.name,
    'sceneTags': value.sceneTags
        .map((item) => item.name)
        .toList(growable: false),
    'photoThemeTags': value.photoThemeTags.toList(growable: false),
  };

  static InsightEvidence _source(Object? value) {
    final raw = _map(value);
    if (!_allowedKeys(raw, const {
      'id',
      'sourcePolicyId',
      'publisher',
      'title',
      'url',
      'observedAt',
      'qualityTier',
      'publishedAt',
      'validFrom',
      'validUntil',
      'license',
      'version',
    })) {
      throw const RegionBriefFailure('invalid_source');
    }
    final url = Uri.tryParse(_string(raw['url'], maximum: 1000));
    if (url == null || url.scheme != 'https') {
      throw const RegionBriefFailure('invalid_source_url');
    }
    return InsightEvidence(
      id: _id(raw['id']),
      sourcePolicyId: _id(raw['sourcePolicyId']),
      publisher: _string(raw['publisher'], maximum: 80),
      title: _string(raw['title'], maximum: 300),
      url: url,
      observedAt: _date(raw['observedAt']),
      qualityTier: switch (raw['qualityTier']) {
        'S' => InsightQualityTier.s,
        'A' => InsightQualityTier.a,
        'B' => InsightQualityTier.b,
        'C' => InsightQualityTier.c,
        _ => throw const RegionBriefFailure('invalid_source_tier'),
      },
      license: _string(raw['license'], maximum: 160),
      version: _string(raw['version'], maximum: 80),
      publishedAt: _nullableDate(raw['publishedAt']),
      validFrom: _nullableDate(raw['validFrom']),
      validUntil: _nullableDate(raw['validUntil']),
    );
  }

  static RegionInsight _insight(Object? value, Set<String> sourceIds) {
    final raw = _map(value);
    if (!_allowedKeys(raw, const {
      'id',
      'regionId',
      'type',
      'title',
      'summary',
      'verification',
      'factIds',
      'evidenceIds',
      'observedAt',
      'expiresAt',
      'placeId',
      'coordinate',
      'startsAt',
      'endsAt',
      'timeSensitive',
      'actionability',
      'sceneTags',
      'photoThemeTags',
    })) {
      throw const RegionBriefFailure('invalid_insight');
    }
    final evidenceIds = _list(
      raw['evidenceIds'],
    ).map(_id).toList(growable: false);
    if (evidenceIds.isEmpty ||
        evidenceIds.any((id) => !sourceIds.contains(id))) {
      throw const RegionBriefFailure('unresolved_evidence');
    }
    final observedAt = _date(raw['observedAt']);
    final expiresAt = _date(raw['expiresAt']);
    if (!expiresAt.isAfter(observedAt)) {
      throw const RegionBriefFailure('invalid_insight_expiry');
    }
    return RegionInsight(
      id: _id(raw['id']),
      regionId: _id(raw['regionId']),
      type: _enum(RegionInsightType.values, raw['type']),
      title: _string(raw['title'], maximum: 120),
      summary: _string(raw['summary'], maximum: 280),
      verification: _enum(InsightVerificationState.values, raw['verification']),
      factIds: _list(raw['factIds']).map(_id).toList(growable: false),
      evidenceIds: evidenceIds,
      observedAt: observedAt,
      expiresAt: expiresAt,
      timeSensitive: raw['timeSensitive'] is bool
          ? raw['timeSensitive']! as bool
          : throw const RegionBriefFailure('invalid_time_sensitive'),
      actionability: _enum(InsightActionability.values, raw['actionability']),
      placeId: raw['placeId'] == null ? null : _id(raw['placeId']),
      point: _coordinateOrNull(raw['coordinate']),
      startsAt: _nullableDate(raw['startsAt']),
      endsAt: _nullableDate(raw['endsAt']),
      sceneTags: _list(
        raw['sceneTags'],
      ).map((item) => _enum(SceneFacet.values, item)).toSet(),
      photoThemeTags: _list(
        raw['photoThemeTags'],
      ).map((item) => _string(item, maximum: 32)).toSet(),
    );
  }

  static ExplorationSceneProfile _profile(Map<String, Object?> raw) {
    if (!_exactKeys(raw, const {
      'physicalScene',
      'facets',
      'settlement',
      'remoteness',
      'altitude',
      'poiDensity',
      'mobility',
      'routeStage',
    })) {
      throw const RegionBriefFailure('invalid_profile');
    }
    return ExplorationSceneProfile(
      physicalScene: _enum(PrimaryScene.values, raw['physicalScene']),
      facets: _list(
        raw['facets'],
      ).map((item) => _enum(SceneFacet.values, item)),
      settlement: _enum(SettlementType.values, raw['settlement']),
      remoteness: _enum(RemotenessLevel.values, raw['remoteness']),
      altitude: _enum(AltitudeBand.values, raw['altitude']),
      poiDensity: _enum(PoiDensityBand.values, raw['poiDensity']),
      mobility: _enum(ActivityState.values, raw['mobility']),
      routeStage: _enum(ContextRouteStage.values, raw['routeStage']),
    );
  }

  static FactBoundText? _textBlockOrNull(Object? value) {
    if (value == null) return null;
    final raw = _map(value);
    if (!_exactKeys(raw, const {'summary', 'factIds'})) {
      throw const RegionBriefFailure('invalid_text_block');
    }
    return FactBoundText(
      summary: _string(raw['summary'], maximum: 120),
      factIds: _list(raw['factIds']).map(_id).toList(growable: false),
    );
  }

  static RegionPhotoTheme _theme(Object? value) {
    final raw = _map(value);
    if (!_exactKeys(raw, const {'id', 'label'})) {
      throw const RegionBriefFailure('invalid_theme');
    }
    return RegionPhotoTheme(
      id: _id(raw['id']),
      label: _string(raw['label'], maximum: 32),
    );
  }

  static GeoPoint? _coordinateOrNull(Object? value) {
    if (value == null) return null;
    final raw = _map(value);
    if (!_exactKeys(raw, const {'latitude', 'longitude', 'system'}) ||
        raw['latitude'] is! num ||
        raw['longitude'] is! num ||
        raw['system'] != 'wgs84') {
      throw const RegionBriefFailure('invalid_coordinate');
    }
    return GeoPoint(
      latitude: (raw['latitude']! as num).toDouble(),
      longitude: (raw['longitude']! as num).toDouble(),
    ).validate();
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const RegionBriefFailure('invalid_object');
    return Map<String, Object?>.from(value);
  }

  static List<Object?> _list(Object? value) {
    if (value is! List) throw const RegionBriefFailure('invalid_array');
    return List<Object?>.from(value);
  }

  static bool _exactKeys(Map<String, Object?> value, Set<String> keys) =>
      value.length == keys.length && _allowedKeys(value, keys);

  static bool _allowedKeys(Map<String, Object?> value, Set<String> keys) =>
      value.keys.every(keys.contains);

  static String _string(Object? value, {required int maximum}) {
    if (value is! String || value.trim().isEmpty || value.length > maximum) {
      throw const RegionBriefFailure('invalid_string');
    }
    return value.trim();
  }

  static String _id(Object? value) {
    final id = _string(value, maximum: 160);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(id)) {
      throw const RegionBriefFailure('invalid_id');
    }
    return id;
  }

  static DateTime _date(Object? value) {
    if (value is! String) throw const RegionBriefFailure('invalid_date');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const RegionBriefFailure('invalid_date');
    return parsed.toUtc();
  }

  static DateTime? _nullableDate(Object? value) =>
      value == null ? null : _date(value);

  static T _enum<T extends Enum>(List<T> values, Object? value) {
    if (value is! String) throw const RegionBriefFailure('invalid_enum');
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    throw const RegionBriefFailure('invalid_enum');
  }
}
