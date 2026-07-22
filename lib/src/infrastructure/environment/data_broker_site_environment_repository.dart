import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/environment/site_environment_facts.dart';
import 'package:luma_nest/src/core/environment/site_environment_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract interface class SiteEnvironmentTransport {
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  });
}

class DioSiteEnvironmentTransport implements SiteEnvironmentTransport {
  DioSiteEnvironmentTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final response = await _dio.getUri<Object?>(
      uri,
      options: Options(headers: headers),
    );
    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid site environment response');
    return Map<String, Object?>.from(data);
  }
}

class DataBrokerSiteEnvironmentRepository implements SiteEnvironmentRepository {
  const DataBrokerSiteEnvironmentRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final SiteEnvironmentTransport transport;

  @override
  Future<SiteEnvironmentFacts> fetch(GeoPoint point) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Site environment repository is unconfigured');
    }
    if (point.coordinateSystem != CoordinateSystem.wgs84) {
      throw const FormatException('Site environment facts require WGS84');
    }
    final uri = Uri.parse(brokerBaseUrl).resolve('/v1/environment/site-facts').replace(
      queryParameters: {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
      },
    );
    final body = await transport.get(
      uri,
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    return SiteEnvironmentFacts.fromJson(body);
  }
}
