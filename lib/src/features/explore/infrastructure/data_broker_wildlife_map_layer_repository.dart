import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/wildlife_map_layer_codec.dart';

abstract interface class WildlifeMapLayerTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioWildlifeMapLayerTransport implements WildlifeMapLayerTransport {
  DioWildlifeMapLayerTransport(this._dio);

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
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    } on WildlifeMapLayerFailure {
      rethrow;
    } on DioException {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.network);
    }
  }
}

class DataBrokerWildlifeMapLayerRepository
    implements WildlifeMapLayerRepository {
  const DataBrokerWildlifeMapLayerRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final WildlifeMapLayerTransport transport;

  @override
  Future<WildlifeMapLayer> fetch({
    required GeoPoint center,
    int radiusKilometers = 20,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const WildlifeMapLayerFailure(
        WildlifeMapLayerFailureKind.configuration,
      );
    }
    center.validate();
    if (center.coordinateSystem != CoordinateSystem.wgs84 ||
        radiusKilometers < 5 ||
        radiusKilometers > 50) {
      throw const WildlifeMapLayerFailure(WildlifeMapLayerFailureKind.response);
    }
    final body = await transport.get(
      '$brokerBaseUrl/v1/wildlife/layers',
      query: {
        'location': '${center.longitude},${center.latitude}',
        'radiusKm': '$radiusKilometers',
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    return WildlifeMapLayerCodec.decode(body, expectedRadius: radiusKilometers);
  }
}
