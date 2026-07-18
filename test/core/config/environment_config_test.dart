import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';

void main() {
  test('missing values report Broker and AMap as unconfigured', () {
    final config = EnvironmentConfig();

    expect(config.isDataBrokerConfigured, isFalse);
    expect(config.isAmapConfigured, isFalse);
  });

  test('configured values trim whitespace and trailing slashes', () {
    final config = EnvironmentConfig(
      amapAndroidKey: ' android-key ',
      dataBrokerBaseUrl: ' https://weather.example.com/// ',
      lumaNestServiceToken: ' service-token ',
    );

    expect(config.dataBrokerBaseUrl, 'https://weather.example.com');
    expect(config.lumaNestServiceToken, 'service-token');
    expect(config.isDataBrokerConfigured, isTrue);
    expect(config.isAmapConfigured, isTrue);
  });

  test('service token is required for the Broker', () {
    final config = EnvironmentConfig(
      dataBrokerBaseUrl: 'https://weather.example.com',
    );

    expect(config.isDataBrokerConfigured, isFalse);
  });

  test('string representation never exposes configured values', () {
    final config = EnvironmentConfig(
      amapAndroidKey: 'android-secret',
      dataBrokerBaseUrl: 'https://weather.example.com',
      lumaNestServiceToken: 'service-secret',
    );

    expect(config.toString(), isNot(contains('secret')));
    expect(config.toString(), isNot(contains('weather.example.com')));
  });
}
