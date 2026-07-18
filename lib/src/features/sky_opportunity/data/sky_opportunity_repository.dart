import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_api.dart';
import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_dto.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

abstract interface class SkyOpportunityRepository {
  Future<DailySkyOpportunities> fetchDaily({
    required double latitude,
    required double longitude,
    SkyOpportunityDailyFocus focus = SkyOpportunityDailyFocus.next,
  });
}

class DataBrokerSkyOpportunityRepository implements SkyOpportunityRepository {
  const DataBrokerSkyOpportunityRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final SkyOpportunityTransport transport;

  @override
  Future<DailySkyOpportunities> fetchDaily({
    required double latitude,
    required double longitude,
    SkyOpportunityDailyFocus focus = SkyOpportunityDailyFocus.next,
  }) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      return DailySkyOpportunities.unavailable();
    }
    final uri = Uri.parse(brokerBaseUrl)
        .resolve('/v1/sky-opportunities/daily')
        .replace(
          queryParameters: {
            'lat': '$latitude',
            'lon': '$longitude',
            'locale': 'zh-CN',
            'focus': focus.name,
          },
        );
    try {
      return parseDailySkyOpportunities(
        await transport.get(
          uri,
          headers: {'Authorization': 'Bearer $serviceToken'},
        ),
      );
    } on Object {
      // SunsetBot is optional creative context. Its failure must never escape
      // into the authoritative weather or safety state.
      return DailySkyOpportunities.unavailable();
    }
  }
}
