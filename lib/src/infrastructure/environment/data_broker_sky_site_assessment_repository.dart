import 'package:luma_nest/src/core/environment/sky_site_assessment.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/infrastructure/environment/data_broker_site_environment_repository.dart';

class DataBrokerSkySiteAssessmentRepository {
  const DataBrokerSkySiteAssessmentRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  static const _maximumCoordinateDifferenceDegrees = 0.00002;

  final String brokerBaseUrl;
  final String serviceToken;
  final SiteEnvironmentTransport transport;

  Future<SkySiteAssessmentEnvelope> fetch(
    GeoPoint point, {
    required DateTime observedAt,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const FormatException(
        'Sky-site assessment repository is unconfigured',
      );
    }
    if (point.coordinateSystem != CoordinateSystem.wgs84) {
      throw const FormatException('Sky-site assessment requires WGS84');
    }
    final canonicalObservedAt = observedAt.toUtc();
    final uri = Uri.parse(brokerBaseUrl)
        .resolve('/v1/environment/site-facts')
        .replace(
          queryParameters: {
            'lat': point.latitude.toString(),
            'lon': point.longitude.toString(),
            'include': 'skyAssessment',
            'at': canonicalObservedAt.toIso8601String(),
          },
        );
    final body = await transport.get(
      uri,
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    final envelope = SkySiteAssessmentEnvelope.fromJson(body);
    final latitudeDifference =
        (envelope.requestedCoordinate.latitude - point.latitude).abs();
    final longitudeDifference =
        (envelope.requestedCoordinate.longitude - point.longitude).abs();
    if (latitudeDifference > _maximumCoordinateDifferenceDegrees ||
        longitudeDifference > _maximumCoordinateDifferenceDegrees) {
      throw const FormatException('Sky-site assessment coordinate mismatch');
    }
    if (envelope.observedAt
            .difference(canonicalObservedAt)
            .inMilliseconds
            .abs() >
        1) {
      throw const FormatException('Sky-site assessment time mismatch');
    }
    return envelope;
  }
}
