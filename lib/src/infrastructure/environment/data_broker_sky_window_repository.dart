import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';

class DataBrokerSkyWindowRepository {
  const DataBrokerSkyWindowRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  static const _maximumCoordinateDifferenceDegrees = 0.00002;

  final String brokerBaseUrl;
  final String serviceToken;
  final SiteEnvironmentTransport transport;

  Future<SkyWindowForecast> fetch(
    GeoPoint point, {
    required DateTime startAt,
    int hours = 72,
    String locale = 'zh-CN',
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException('Sky-window repository is unconfigured');
    }
    if (point.coordinateSystem != CoordinateSystem.wgs84) {
      throw const FormatException('Sky-window forecast requires WGS84');
    }
    if (hours < 6 || hours > 72 || (locale != 'zh-CN' && locale != 'en')) {
      throw const FormatException('Invalid sky-window request');
    }
    final canonicalStart = startAt.toUtc();
    final uri = Uri.parse(brokerBaseUrl)
        .resolve('/v1/environment/sky-windows')
        .replace(
          queryParameters: {
            'lat': point.latitude.toString(),
            'lon': point.longitude.toString(),
            'start': canonicalStart.toIso8601String(),
            'hours': hours.toString(),
            'locale': locale,
          },
        );
    final body = await transport.get(
      uri,
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    final forecast = SkyWindowForecast.fromJson(body);
    final latitudeDifference =
        (forecast.requestedCoordinate.latitude - point.latitude).abs();
    final longitudeDifference =
        (forecast.requestedCoordinate.longitude - point.longitude).abs();
    if (latitudeDifference > _maximumCoordinateDifferenceDegrees ||
        longitudeDifference > _maximumCoordinateDifferenceDegrees) {
      throw const FormatException('Sky-window coordinate mismatch');
    }
    if (forecast.requestedStartAt
            .difference(canonicalStart)
            .inMilliseconds
            .abs() >
        1) {
      throw const FormatException('Sky-window start time mismatch');
    }
    return forecast;
  }
}
