export const sunsetBotDefaults = Object.freeze({
  baseUrl: 'https://sunsetbot.top',
  cityPath: '/',
  mapPath: '/map/',
  userAgent: 'LumaNest/1.0 SkyOpportunityService',
  providerLocalTimeZone: 'Asia/Shanghai',
  timeoutMs: 12_000,
  imageTimeoutMs: 20_000,
  maxAttempts: 2,
  retryDelayMs: 500,
  freshTtlSeconds: 5_400,
  staleTtlSeconds: 21_600,
  maxGlobalConcurrency: 4,
  maxCityConcurrency: 2,
  circuitFailureThreshold: 5,
  circuitRollingWindowSeconds: 600,
  circuitFailureRateThreshold: .60,
  circuitOpenSeconds: 900,
  models: Object.freeze(['GFS', 'EC']),
  proactiveDisplayThreshold: .20,
  paperNoteThreshold: .60,
  attribution: '晚霞预测数据来源：SunsetBot',
});

export function sunsetBotConfig(settings = {}, { baseUrl } = {}) {
  return Object.freeze({
    ...sunsetBotDefaults,
    baseUrl: baseUrl?.trim() || sunsetBotDefaults.baseUrl,
    enabled: settings.sunsetbotProviderEnabled ?? true,
    cardEnabled: settings.skyOpportunityCardEnabled ?? true,
    mapEnabled: settings.skyOpportunityMapEnabled ?? false,
    tomorrowSunsetEnabled: settings.skyOpportunityTomorrowSunsetEnabled ?? false,
    timeoutMs: settings.sunsetbotTimeoutMs ?? sunsetBotDefaults.timeoutMs,
    maxAttempts: settings.sunsetbotMaxAttempts ?? sunsetBotDefaults.maxAttempts,
    retryDelayMs: settings.sunsetbotRetryDelayMs ?? sunsetBotDefaults.retryDelayMs,
    freshTtlSeconds: settings.sunsetbotFreshTtlSeconds ?? sunsetBotDefaults.freshTtlSeconds,
    staleTtlSeconds: settings.sunsetbotStaleTtlSeconds ?? sunsetBotDefaults.staleTtlSeconds,
    maxGlobalConcurrency:
      settings.sunsetbotMaxGlobalConcurrency ?? sunsetBotDefaults.maxGlobalConcurrency,
    maxCityConcurrency:
      settings.sunsetbotMaxCityConcurrency ?? sunsetBotDefaults.maxCityConcurrency,
    circuitFailureThreshold:
      settings.sunsetbotCircuitFailureThreshold ?? sunsetBotDefaults.circuitFailureThreshold,
    circuitRollingWindowSeconds:
      settings.sunsetbotCircuitRollingWindowSeconds ??
      sunsetBotDefaults.circuitRollingWindowSeconds,
    circuitFailureRateThreshold:
      settings.sunsetbotCircuitFailureRateThreshold ??
      sunsetBotDefaults.circuitFailureRateThreshold,
    circuitOpenSeconds:
      settings.sunsetbotCircuitOpenSeconds ?? sunsetBotDefaults.circuitOpenSeconds,
    proactiveDisplayThreshold:
      settings.skyOpportunityDisplayThreshold ?? sunsetBotDefaults.proactiveDisplayThreshold,
    paperNoteThreshold:
      settings.skyOpportunityPaperThreshold ?? sunsetBotDefaults.paperNoteThreshold,
  });
}
