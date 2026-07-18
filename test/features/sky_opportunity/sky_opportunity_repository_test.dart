import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_api.dart';
import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_repository.dart';

void main() {
  test(
    'requests only the LumaNest daily API and parses the unified model',
    () async {
      final transport = _Transport(_dailyResponse());
      final repository = DataBrokerSkyOpportunityRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: transport,
      );

      final value = await repository.fetchDaily(
        latitude: 30.2741,
        longitude: 120.1551,
      );

      expect(transport.uri.host, 'broker.example.com');
      expect(transport.uri.path, '/v1/sky-opportunities/daily');
      expect(transport.uri.queryParameters['lat'], '30.2741');
      expect(transport.uri.queryParameters['focus'], 'next');
      expect(transport.headers, {'Authorization': 'Bearer token'});
      expect(value.todaySunset?.level, 'moderate');
      expect(value.todaySunset?.models, hasLength(2));
      expect(value.todaySunset?.models.first.providerLabel, '小烧到中烧');
      expect(value.todaySunset?.presentation.ambientStrength, .13);
      expect(value.flags.cardEnabled, isTrue);
    },
  );

  test(
    'malformed or failed enhancement returns a fully collapsed state',
    () async {
      final repository = DataBrokerSkyOpportunityRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: _Transport({'todaySunset': 'broken'}),
      );
      final value = await repository.fetchDaily(latitude: 30, longitude: 120);
      expect(value.values, isEmpty);
      expect(value.flags.providerEnabled, isFalse);
    },
  );

  test(
    'rejects a legacy numeric response instead of silently accepting it',
    () async {
      final response = _dailyResponse();
      final forecast = response['todaySunset']! as Map<String, Object?>;
      final data = forecast['data']! as Map<String, Object?>;
      data['summary'] = {
        ...Map<String, Object?>.from(data['summary']! as Map),
        'score': .36,
      };
      final repository = DataBrokerSkyOpportunityRepository(
        brokerBaseUrl: 'https://broker.example.com',
        serviceToken: 'token',
        transport: _Transport(response),
      );

      final value = await repository.fetchDaily(latitude: 30, longitude: 120);

      expect(value.todaySunset, isNull);
    },
  );
}

Map<String, Object?> _dailyResponse() => {
  'status': 'ok',
  'todaySunset': {'status': 'ok', 'data': _forecastResponse()},
  'tomorrowSunrise': {'status': 'unavailable', 'data': null},
  'tomorrowSunset': {'status': 'unavailable', 'data': null},
  'featureFlags': {
    'sunsetbotProviderEnabled': true,
    'skyOpportunityCardEnabled': true,
    'skyOpportunityNotificationEnabled': false,
    'skyOpportunityMapEnabled': false,
  },
};

Map<String, Object?> _forecastResponse() => {
  'id': 'skyopp_hangzhou_20260718_sunset',
  'source': 'sunsetbot',
  'location': {
    'requestedCity': '杭州',
    'resolvedCity': '杭州',
    'locationPrecision': 'city',
  },
  'event': {
    'type': 'sunset',
    'dayOffset': 0,
    'eventTime': '2026-07-18T18:59:55+08:00',
    'providerLocalTimeZone': 'Asia/Shanghai',
  },
  'summary': {
    'level': 'moderate',
    'label': '有机会',
    'confidence': 'high',
    'agreement': 'strong',
    'primaryReason': '双模型判断较一致',
  },
  'atmosphere': {'clarityLevel': 'good', 'clarityLabel': '大气较通透'},
  'models': [
    {
      'model': 'GFS',
      'providerLabel': '小烧到中烧',
      'eventTime': '2026-07-18T18:59:55+08:00',
      'status': 'ok',
      'parseStatus': 'ok',
    },
    {
      'model': 'EC',
      'providerLabel': '中烧',
      'eventTime': '2026-07-18T18:59:55+08:00',
      'status': 'ok',
      'parseStatus': 'ok',
    },
  ],
  'freshness': {
    'fetchedAt': '2026-07-18T09:10:00Z',
    'expiresAt': '2026-07-18T10:40:00Z',
    'cacheStatus': 'miss',
    'isStale': false,
  },
  'provider': {
    'name': 'SunsetBot',
    'attribution': '晚霞预测数据来源：SunsetBot',
    'providerStatus': 'healthy',
  },
  'presentation': {
    'proactiveEligible': true,
    'paperEligible': false,
    'notificationEligible': false,
    'ambientStrength': .13,
  },
};

class _Transport implements SkyOpportunityTransport {
  _Transport(this.response);
  final Map<String, Object?> response;
  late Uri uri;
  late Map<String, String> headers;

  @override
  Future<Map<String, Object?>> get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return response;
  }
}
