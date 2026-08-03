import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/core/environment/provider_facts_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract interface class ProviderFactsTransport {
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  });
}

class DioProviderFactsTransport implements ProviderFactsTransport {
  DioProviderFactsTransport(this._dio);

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
    if (data is! Map) {
      throw const FormatException('Invalid provider facts response');
    }
    return Map<String, Object?>.from(data);
  }
}

class DataBrokerProviderFactsRepository implements ProviderFactsRepository {
  const DataBrokerProviderFactsRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  static const _maximumCoordinateDifferenceDegrees = 0.00002;

  final String brokerBaseUrl;
  final String serviceToken;
  final ProviderFactsTransport transport;

  @override
  Future<ProviderFactsBundle> fetch(
    GeoPoint point, {
    int radiusKm = 25,
    String locale = 'zh-CN',
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Provider facts repository is unconfigured');
    }
    if (point.coordinateSystem != CoordinateSystem.wgs84 ||
        radiusKm < 1 ||
        radiusKm > 50) {
      throw const FormatException('Provider facts require bounded WGS84 input');
    }
    final uri = Uri.parse(brokerBaseUrl)
        .resolve('/v1/environment/provider-facts')
        .replace(
          queryParameters: {
            'lat': point.latitude.toString(),
            'lon': point.longitude.toString(),
            'radiusKm': radiusKm.toString(),
            'locale': locale,
          },
        );
    final body = await transport.get(
      uri,
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    final facts = ProviderFactsBundle.fromJson(body);
    if ((facts.requestedCoordinate.latitude - point.latitude).abs() >
            _maximumCoordinateDifferenceDegrees ||
        (facts.requestedCoordinate.longitude - point.longitude).abs() >
            _maximumCoordinateDifferenceDegrees) {
      throw const FormatException(
        'Provider facts response coordinate mismatch',
      );
    }
    return facts;
  }
}
