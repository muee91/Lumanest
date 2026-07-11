import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';

void main() {
  test('missing values report both integrations as unconfigured', () {
    final config = EnvironmentConfig();

    expect(config.isAmapConfigured, isFalse);
    expect(config.isQWeatherConfigured, isFalse);
  });

  test('configured values trim whitespace and host trailing slashes', () {
    final config = EnvironmentConfig(
      amapAndroidKey: '  amap-secret  ',
      qweatherApiHost: ' https://example.qweatherapi.com/// ',
      qweatherTokenEndpoint: ' https://weather.example.com/v1/qweather/token/// ',
      lumaNestServiceToken: '  broker-secret ',
    );

    expect(config.amapAndroidKey, 'amap-secret');
    expect(config.qweatherApiHost, 'https://example.qweatherapi.com');
    expect(config.qweatherTokenEndpoint, 'https://weather.example.com/v1/qweather/token');
    expect(config.lumaNestServiceToken, 'broker-secret');
    expect(config.isAmapConfigured, isTrue);
    expect(config.isQWeatherConfigured, isTrue);
  });

  test('string representation never exposes key values', () {
    final config = EnvironmentConfig(
      amapAndroidKey: 'amap-secret',
      qweatherApiHost: 'https://example.qweatherapi.com',
      qweatherTokenEndpoint: 'https://weather.example.com/v1/qweather/token',
      lumaNestServiceToken: 'broker-secret',
    );

    expect(config.toString(), isNot(contains('amap-secret')));
    expect(config.toString(), isNot(contains('broker-secret')));
  });
}
