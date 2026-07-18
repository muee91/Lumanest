import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/popular_place_evidence.dart';

abstract interface class PopularPlaceEvidenceTransport {
  Future<Map<String, Object?>> post(
    String url, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
  });
}

class DioPopularPlaceEvidenceTransport
    implements PopularPlaceEvidenceTransport {
  DioPopularPlaceEvidenceTransport(this._dio);

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
    return const {};
  }
}

class DataBrokerPopularPlaceEvidenceRepository
    implements PopularPlaceEvidenceRepository {
  const DataBrokerPopularPlaceEvidenceRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
    this.now = DateTime.now,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final PopularPlaceEvidenceTransport transport;
  final DateTime Function() now;

  @override
  Future<List<PopularPlaceEvidence>> fetch({
    required GeoPoint center,
    required int radiusMeters,
    required String focus,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) return const [];
    final requestedAt = now().toUtc();
    try {
      final body = await transport.post(
        '$brokerBaseUrl/v1/explore/discover',
        body: {
          'missionType': 'popularPlaces',
          'focus': focus,
          'locale': 'zh-CN',
          'region': {
            'latitude': center.latitude,
            'longitude': center.longitude,
            'radiusMeters': radiusMeters.clamp(100, 50000),
          },
          'timeRange': {
            'startsAt': requestedAt.toIso8601String(),
            'endsAt': requestedAt
                .add(const Duration(days: 7))
                .toIso8601String(),
          },
          'routeCorridor': null,
          'interests': const ['photography'],
        },
        headers: {
          'Authorization': 'Bearer $serviceToken',
          'Content-Type': 'application/json',
        },
      );
      if (body['missionType'] != 'popularPlaces' || body['items'] is! List) {
        return const [];
      }
      return List.unmodifiable(
        (body['items'] as List)
            .whereType<Map>()
            .map((raw) => _parse(Map<String, Object?>.from(raw)))
            .whereType<PopularPlaceEvidence>(),
      );
    } on Object {
      // Popularity evidence is optional enrichment. POI and route results must
      // remain usable when search, the discovery worker or the LLM is absent.
      return const [];
    }
  }

  static PopularPlaceEvidence? _parse(Map<String, Object?> raw) {
    final coordinate = raw['coordinate'];
    final evidence = raw['evidence'];
    if (raw['id'] is! String ||
        raw['title'] is! String ||
        coordinate is! Map ||
        coordinate['latitude'] is! num ||
        coordinate['longitude'] is! num ||
        coordinate['system'] != 'wgs84' ||
        raw['distanceMeters'] is! int ||
        evidence is! List ||
        evidence.isEmpty) {
      return null;
    }
    return PopularPlaceEvidence(
      id: raw['id'] as String,
      title: raw['title'] as String,
      point: GeoPoint(
        latitude: (coordinate['latitude'] as num).toDouble(),
        longitude: (coordinate['longitude'] as num).toDouble(),
      ).validate(),
      distanceMeters: raw['distanceMeters'] as int,
      sourceCount: evidence.length.clamp(1, 4),
      address: raw['address'] is String ? raw['address'] as String : null,
    );
  }
}
