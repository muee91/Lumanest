import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/elevation_profile.dart';

abstract interface class ElevationProfileTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioElevationProfileTransport implements ElevationProfileTransport {
  DioElevationProfileTransport(this._dio);

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
    throw const FormatException('Invalid elevation response');
  }
}

class DataBrokerElevationProfileRepository
    implements ElevationProfileRepository {
  const DataBrokerElevationProfileRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final ElevationProfileTransport transport;

  @override
  Future<ElevationProfile> fetch(List<GeoPoint> points) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Elevation broker is not configured');
    }
    if (points.length < 2 || points.length > 64) {
      throw const FormatException('Elevation sample count is out of range');
    }
    final body = await transport.get(
      '$brokerBaseUrl/v1/elevation/profile',
      query: {
        'locations': points
            .map((point) => '${point.longitude},${point.latitude}')
            .join(';'),
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    final source = body['source'];
    final rawElevations = body['elevations'];
    if (source is! String ||
        source.isEmpty ||
        rawElevations is! List ||
        rawElevations.length != points.length) {
      throw const FormatException('Invalid elevation profile');
    }
    final elevations = rawElevations
        .whereType<num>()
        .map((value) {
          final elevation = value.toDouble();
          if (!elevation.isFinite) {
            throw const FormatException('Invalid elevation value');
          }
          return elevation;
        })
        .toList(growable: false);
    if (elevations.length != points.length) {
      throw const FormatException('Missing elevation values');
    }
    return ElevationProfile(source: source, elevations: elevations);
  }
}
