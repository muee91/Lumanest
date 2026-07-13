import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

abstract interface class LocationSearchTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioLocationSearchTransport implements LocationSearchTransport {
  DioLocationSearchTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        url,
        queryParameters: query,
        options: Options(headers: headers),
      );
      if (response.data case final Map body) {
        return Map<String, Object?>.from(body);
      }
      throw const LocationSearchFailure(LocationSearchFailureKind.response);
    } on LocationSearchFailure {
      rethrow;
    } on DioException {
      throw const LocationSearchFailure(LocationSearchFailureKind.network);
    }
  }
}

class AmapLocationSearchRepository implements LocationSearchRepository {
  const AmapLocationSearchRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final LocationSearchTransport transport;

  @override
  Future<List<LocationSearchResult>> search(String keywords) async {
    final query = keywords.trim();
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const LocationSearchFailure(
        LocationSearchFailureKind.configuration,
      );
    }
    if (query.isEmpty) return const [];
    final body = await transport.get(
      '$brokerBaseUrl/v1/amap/search',
      query: {'keywords': query, 'offset': '10'},
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    if (body['status'] != '1' || body['pois'] is! List) {
      throw const LocationSearchFailure(LocationSearchFailureKind.response);
    }
    return (body['pois'] as List)
        .whereType<Map>()
        .map((raw) => _parse(Map<String, Object?>.from(raw)))
        .whereType<LocationSearchResult>()
        .toList(growable: false);
  }

  LocationSearchResult? _parse(Map<String, Object?> raw) {
    final name = raw['name'];
    final location = raw['location'];
    if (name is! String || name.isEmpty || location is! String) return null;
    final values = location.split(',');
    if (values.length != 2) return null;
    final longitude = double.tryParse(values[0]);
    final latitude = double.tryParse(values[1]);
    if (longitude == null || latitude == null) return null;
    return LocationSearchResult(
      id: raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : '$name@$location',
      name: name,
      point: GeoPoint(
        latitude: latitude,
        longitude: longitude,
        coordinateSystem: CoordinateSystem.gcj02,
      ).validate(),
      address: raw['address'] is String && (raw['address'] as String).isNotEmpty
          ? raw['address'] as String
          : null,
    );
  }
}
