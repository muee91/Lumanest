class EnvironmentConfig {
  factory EnvironmentConfig({
    String amapAndroidKey = '',
    String qweatherApiHost = '',
    String qweatherApiKey = '',
  }) {
    return EnvironmentConfig._(
      amapAndroidKey: amapAndroidKey.trim(),
      qweatherApiHost: _normalizeHost(qweatherApiHost),
      qweatherApiKey: qweatherApiKey.trim(),
    );
  }

  const EnvironmentConfig._({
    required this.amapAndroidKey,
    required this.qweatherApiHost,
    required this.qweatherApiKey,
  });

  factory EnvironmentConfig.fromEnvironment() {
    return EnvironmentConfig(
      amapAndroidKey: const String.fromEnvironment('AMAP_ANDROID_KEY'),
      qweatherApiHost: const String.fromEnvironment('QWEATHER_API_HOST'),
      qweatherApiKey: const String.fromEnvironment('QWEATHER_API_KEY'),
    );
  }

  final String amapAndroidKey;
  final String qweatherApiHost;
  final String qweatherApiKey;

  bool get isAmapConfigured => amapAndroidKey.isNotEmpty;

  bool get isQWeatherConfigured =>
      qweatherApiHost.isNotEmpty && qweatherApiKey.isNotEmpty;

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
