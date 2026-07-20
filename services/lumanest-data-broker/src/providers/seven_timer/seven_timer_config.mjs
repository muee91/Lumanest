export const sevenTimerDefaults = Object.freeze({
  baseUrl: 'https://www.7timer.info',
  timeoutMs: 12_000,
  maxAttempts: 2,
  retryDelayMs: 500,
  maximumResponseBytes: 1024 * 1024,
  userAgent: 'LumaNest/1.0 SevenTimerProvider',
  astroFreshTtlSeconds: 10_800,
  meteoFreshTtlSeconds: 10_800,
  twoFreshTtlSeconds: 21_600,
  staleTtlSeconds: 43_200,
  adminTestTimeoutMs: 8_000,
  adminTestCooldownSeconds: 10,
  adminTestMaxConcurrency: 1,
});

export function sevenTimerConfig(settings = {}, { baseUrl } = {}) {
  return Object.freeze({
    ...sevenTimerDefaults,
    baseUrl: baseUrl?.trim() || sevenTimerDefaults.baseUrl,
    enabled: settings.sevenTimerProviderEnabled ?? true,
    timeoutMs: settings.sevenTimerTimeoutMs ?? sevenTimerDefaults.timeoutMs,
    maxAttempts: settings.sevenTimerMaxAttempts ?? sevenTimerDefaults.maxAttempts,
    retryDelayMs: settings.sevenTimerRetryDelayMs ?? sevenTimerDefaults.retryDelayMs,
    astroFreshTtlSeconds:
      settings.sevenTimerAstroFreshTtlSeconds ?? sevenTimerDefaults.astroFreshTtlSeconds,
    meteoFreshTtlSeconds:
      settings.sevenTimerMeteoFreshTtlSeconds ?? sevenTimerDefaults.meteoFreshTtlSeconds,
    twoFreshTtlSeconds:
      settings.sevenTimerTwoFreshTtlSeconds ?? sevenTimerDefaults.twoFreshTtlSeconds,
    staleTtlSeconds:
      settings.sevenTimerStaleTtlSeconds ?? sevenTimerDefaults.staleTtlSeconds,
    adminTestTimeoutMs:
      settings.sevenTimerAdminTestTimeoutMs ?? sevenTimerDefaults.adminTestTimeoutMs,
    adminTestCooldownSeconds:
      settings.sevenTimerAdminTestCooldownSeconds ?? sevenTimerDefaults.adminTestCooldownSeconds,
    adminTestMaxConcurrency:
      settings.sevenTimerAdminTestMaxConcurrency ?? sevenTimerDefaults.adminTestMaxConcurrency,
  });
}

export function freshTtlForProduct(config, product) {
  return {
    astro: config.astroFreshTtlSeconds,
    meteo: config.meteoFreshTtlSeconds,
    two: config.twoFreshTtlSeconds,
  }[product];
}
