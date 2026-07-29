import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

abstract interface class VerifiedPlaceMediaTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioVerifiedPlaceMediaTransport implements VerifiedPlaceMediaTransport {
  DioVerifiedPlaceMediaTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    final response = await _dio.get<Object?>(
      url,
      queryParameters: query,
      options: Options(headers: headers),
    );
    if (response.data case final Map body) {
      return Map<String, Object?>.from(body);
    }
    return const {};
  }
}

class VerifiedPlaceMediaRepository {
  const VerifiedPlaceMediaRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final VerifiedPlaceMediaTransport transport;

  Future<List<NearbyPlaceMedia>> fetch(NearbyPlace place) => _fetch(
    id: place.id,
    name: place.name,
    point: place.point,
    city: place.cityName,
  );

  Future<List<NearbyPlaceMedia>> fetchSearchResult(
    LocationSearchResult result,
  ) => _fetch(id: result.id, name: result.name, point: result.point);

  Future<List<NearbyPlaceMedia>> _fetch({
    required String id,
    required String name,
    required GeoPoint point,
    String? city,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) return const [];
    final sourcePoint = point.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(point)
        : point;
    final query = <String, String>{
      'name': name,
      'lat': sourcePoint.latitude.toStringAsFixed(6),
      'lon': sourcePoint.longitude.toStringAsFixed(6),
      'poiId': id,
    };
    if (city != null) query['city'] = city;
    try {
      final body = await transport.get(
        '$brokerBaseUrl/v1/explore/place-media',
        query: query,
        headers: {'Authorization': 'Bearer $serviceToken'},
      );
      if (body['status'] != 'ok' || body['media'] is! List) return const [];
      final parsed = (body['media'] as List)
          .whereType<Map>()
          .map((item) => _parse(Map<String, Object?>.from(item)))
          .whereType<NearbyPlaceMedia>()
          .toList(growable: false);
      parsed.sort(
        (first, second) => first.sourceTier == second.sourceTier
            ? 0
            : first.sourceTier == 'primary'
            ? -1
            : 1,
      );
      return List.unmodifiable(parsed);
    } on DioException {
      return const [];
    } on Object {
      return const [];
    }
  }

  NearbyPlaceMedia? _parse(Map<String, Object?> raw) {
    final id = raw['id'];
    final proxyPath = raw['proxyPath'];
    final attribution = _text(raw['attribution']);
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{24}$').hasMatch(id) ||
        proxyPath is! String ||
        !RegExp(
          r'^/v1/explore/media/[A-Za-z0-9_-]{16,2800}$',
        ).hasMatch(proxyPath) ||
        attribution == null) {
      return null;
    }
    final base = Uri.tryParse(brokerBaseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    final mediaUrl = base.resolve(proxyPath);
    final sourceText = _text(raw['sourceUrl']);
    final sourceUrl = sourceText == null ? null : Uri.tryParse(sourceText);
    if ((mediaUrl.scheme != 'https' && mediaUrl.scheme != 'http') ||
        sourceUrl == null ||
        sourceUrl.scheme != 'https') {
      return null;
    }
    return NearbyPlaceMedia(
      id: id,
      url: mediaUrl.toString(),
      attribution: attribution,
      title: _text(raw['title']),
      creator: _text(raw['creator']),
      license: _text(raw['license']),
      sourceUrl: sourceUrl.toString(),
      matchBasis: switch (raw['matchBasis']) {
        'name' => 'name',
        'wikidataEntity' => 'wikidataEntity',
        'amapPoiId' => 'amapPoiId',
        _ => null,
      },
      sourceTier: raw['sourceTier'] == 'supplemental'
          ? 'supplemental'
          : 'primary',
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
