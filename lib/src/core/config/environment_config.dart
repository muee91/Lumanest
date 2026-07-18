class EnvironmentConfig {
  factory EnvironmentConfig({
    String amapAndroidKey = '',
    String dataBrokerBaseUrl = '',
    String lumaNestServiceToken = '',
    String sentryDsn = '',
  }) {
    return EnvironmentConfig._(
      amapAndroidKey: amapAndroidKey.trim(),
      dataBrokerBaseUrl: _normalizeHost(dataBrokerBaseUrl),
      lumaNestServiceToken: lumaNestServiceToken.trim(),
      sentryDsn: sentryDsn.trim(),
    );
  }

  const EnvironmentConfig._({
    required this.amapAndroidKey,
    required this.dataBrokerBaseUrl,
    required this.lumaNestServiceToken,
    required this.sentryDsn,
  });

  factory EnvironmentConfig.fromEnvironment() => EnvironmentConfig(
    amapAndroidKey: const String.fromEnvironment('AMAP_ANDROID_KEY'),
    dataBrokerBaseUrl: const String.fromEnvironment('LUMANEST_BROKER_BASE_URL'),
    lumaNestServiceToken: const String.fromEnvironment(
      'LUMANEST_SERVICE_TOKEN',
    ),
    sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
  );

  final String amapAndroidKey;
  final String dataBrokerBaseUrl;
  final String lumaNestServiceToken;
  final String sentryDsn;

  bool get isAmapConfigured => amapAndroidKey.isNotEmpty;

  bool get isDataBrokerConfigured =>
      dataBrokerBaseUrl.isNotEmpty && lumaNestServiceToken.isNotEmpty;

  bool get isSentryConfigured => sentryDsn.isNotEmpty;

  static String _normalizeHost(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  @override
  String toString() =>
      'EnvironmentConfig('
      'amapConfigured: $isAmapConfigured, '
      'brokerConfigured: $isDataBrokerConfigured, '
      'sentryConfigured: $isSentryConfigured)';
}
