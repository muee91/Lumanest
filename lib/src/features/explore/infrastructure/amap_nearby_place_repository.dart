import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';

abstract interface class AmapDataTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioAmapDataTransport implements AmapDataTransport {
  DioAmapDataTransport(this._dio);

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
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.response);
    } on NearbyPlaceFailure {
      rethrow;
    } on DioException {
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.network);
    }
  }
}

class AmapNearbyPlaceRepository implements NearbyPlaceRepository {
  const AmapNearbyPlaceRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final AmapDataTransport transport;

  @override
  Future<List<NearbyPlace>> fetchNearby({
    required GeoPoint center,
    required NearbyPlaceCategory category,
    int radiusMeters = 5000,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.configuration);
    }
    final mapCenter = center.coordinateSystem == CoordinateSystem.wgs84
        ? ChinaCoordinateConverter.wgs84ToGcj02(center)
        : center;
    final body = await transport.get(
      '$brokerBaseUrl/v1/amap/nearby',
      query: {
        'location': '${mapCenter.longitude},${mapCenter.latitude}',
        'keywords': category.keyword,
        'radius': radiusMeters.clamp(100, 50000).toString(),
        'offset': '25',
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    if (body['status'] != '1' || body['pois'] is! List) {
      throw const NearbyPlaceFailure(NearbyPlaceFailureKind.response);
    }

    return (body['pois'] as List)
        .whereType<Map>()
        .map((raw) => _parsePlace(Map<String, Object?>.from(raw), category))
        .whereType<NearbyPlace>()
        .toList(growable: false);
  }

  NearbyPlace? _parsePlace(
    Map<String, Object?> raw,
    NearbyPlaceCategory category,
  ) {
    final name = raw['name'];
    final location = raw['location'];
    if (name is! String || name.isEmpty || location is! String) return null;
    final parts = location.split(',');
    if (parts.length != 2) return null;
    final longitude = double.tryParse(parts[0]);
    final latitude = double.tryParse(parts[1]);
    if (longitude == null || latitude == null) return null;
    final distance = int.tryParse('${raw['distance'] ?? ''}') ?? 0;
    final id = raw['id'] is String && (raw['id'] as String).isNotEmpty
        ? raw['id'] as String
        : '$name@$location';
    final address = raw['address'];
    return NearbyPlace(
      id: id,
      name: name,
      category: category,
      point: GeoPoint(
        latitude: latitude,
        longitude: longitude,
        coordinateSystem: CoordinateSystem.gcj02,
      ).validate(),
      distanceMeters: distance,
      address: address is String && address.isNotEmpty ? address : null,
    );
  }
}
