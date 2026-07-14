import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';

void main() {
  test('missing values report both integrations as unconfigured', () {
    final config = EnvironmentConfig();

    expect(config.isAmapConfigured, isFalse);
    expect(config.isQWeatherConfigured, isFalse);
    expect(config.isSentryConfigured, isFalse);
  });

  test('configured values trim whitespace and host trailing slashes', () {
    final config = EnvironmentConfig(
      amapAndroidKey: '  amap-secret  ',
      qweatherApiHost: ' https://example.qweatherapi.com/// ',
      qweatherTokenEndpoint:
          ' https://weather.example.com/v1/qweather/token/// ',
      lumaNestServiceToken: '  broker-secret ',
      sentryDsn: ' https://public@example.ingest.sentry.io/123 ',
    );

    expect(config.amapAndroidKey, 'amap-secret');
    expect(config.qweatherApiHost, 'https://example.qweatherapi.com');
    expect(
      config.qweatherTokenEndpoint,
      'https://weather.example.com/v1/qweather/token',
    );
    expect(config.dataBrokerBaseUrl, 'https://weather.example.com');
    expect(config.isDataBrokerConfigured, isTrue);
    expect(config.lumaNestServiceToken, 'broker-secret');
    expect(config.isAmapConfigured, isTrue);
    expect(config.isQWeatherConfigured, isTrue);
    expect(config.isSentryConfigured, isTrue);
    expect(config.sentryDsn, 'https://public@example.ingest.sentry.io/123');
  });

  test(
    'Broker configuration does not require the legacy QWeather API host',
    () {
      final config = EnvironmentConfig(
        qweatherTokenEndpoint: 'https://weather.example.com/v1/qweather/token',
        lumaNestServiceToken: 'broker-secret',
      );

      expect(config.isDataBrokerConfigured, isTrue);
      expect(config.isQWeatherConfigured, isFalse);
    },
  );

  test('string representation never exposes key values', () {
    final config = EnvironmentConfig(
      amapAndroidKey: 'amap-secret',
      qweatherApiHost: 'https://example.qweatherapi.com',
      qweatherTokenEndpoint: 'https://weather.example.com/v1/qweather/token',
      lumaNestServiceToken: 'broker-secret',
      sentryDsn: 'https://public@example.ingest.sentry.io/123',
    );

    expect(config.toString(), isNot(contains('amap-secret')));
    expect(config.toString(), isNot(contains('broker-secret')));
    expect(config.toString(), isNot(contains('example.ingest.sentry.io')));
  });
}
