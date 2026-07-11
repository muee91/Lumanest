class EnvironmentConfig {
  factory EnvironmentConfig({
    String amapAndroidKey = '',
    String qweatherApiHost = '',
    String qweatherTokenEndpoint = '',
    String lumaNestServiceToken = '',
  }) {
    return EnvironmentConfig._(
      amapAndroidKey: amapAndroidKey.trim(),
      qweatherApiHost: _normalizeHost(qweatherApiHost),
      qweatherTokenEndpoint: _normalizeHost(qweatherTokenEndpoint),
      lumaNestServiceToken: lumaNestServiceToken.trim(),
    );
  }

  const EnvironmentConfig._({
    required this.amapAndroidKey,
    required this.qweatherApiHost,
    required this.qweatherTokenEndpoint,
    required this.lumaNestServiceToken,
  });

  factory EnvironmentConfig.fromEnvironment() {
    return EnvironmentConfig(
      amapAndroidKey: const String.fromEnvironment('AMAP_ANDROID_KEY'),
      qweatherApiHost: const String.fromEnvironment('QWEATHER_API_HOST'),
      qweatherTokenEndpoint: const String.fromEnvironment(
        'QWEATHER_TOKEN_ENDPOINT',
      ),
      lumaNestServiceToken: const String.fromEnvironment(
        'LUMANEST_SERVICE_TOKEN',
      ),
    );
  }

  final String amapAndroidKey;
  final String qweatherApiHost;
  final String qweatherTokenEndpoint;
  final String lumaNestServiceToken;

  bool get isAmapConfigured => amapAndroidKey.isNotEmpty;

  bool get isQWeatherConfigured =>
      qweatherApiHost.isNotEmpty &&
      qweatherTokenEndpoint.isNotEmpty &&
      lumaNestServiceToken.isNotEmpty;

  static String _normalizeHost(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  @override
  String toString() {
    return 'EnvironmentConfig('
        'amapConfigured: $isAmapConfigured, '
        'qweatherConfigured: $isQWeatherConfigured)';
  }
}
