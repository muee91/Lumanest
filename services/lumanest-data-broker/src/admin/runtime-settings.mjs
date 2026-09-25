const definitions = Object.freeze({
  aiEnabled: Object.freeze({ type: 'boolean', defaultValue: true }),
  assistantWebSearchEnabled: Object.freeze({ type: 'boolean', defaultValue: false }),
  aiTimeoutMs: Object.freeze({ type: 'integer', minimum: 2_000, maximum: 30_000, defaultValue: 8_000 }),
  wildlifeRadiusKm: Object.freeze({ type: 'integer', minimum: 5, maximum: 50, defaultValue: 20 }),
  wildlifeCacheTtlMinutes: Object.freeze({ type: 'integer', minimum: 5, maximum: 1_440, defaultValue: 60 }),
  elevationCacheTtlMinutes: Object.freeze({ type: 'integer', minimum: 60, maximum: 10_080, defaultValue: 1_440 }),
  elevationMaximumSamples: Object.freeze({ type: 'integer', minimum: 2, maximum: 64, defaultValue: 64 }),
  discoveryLocationWarmupEnabled: Object.freeze({ type: 'boolean', defaultValue: true }),
  discoveryLocationWarmupRadiusMeters: Object.freeze({ type: 'integer', minimum: 5_000, maximum: 30_000, defaultValue: 15_000 }),
  upstreamTimeoutMs: Object.freeze({ type: 'integer', minimum: 2_000, maximum: 30_000, defaultValue: 10_000 }),
  minimumOpportunityConfidence: Object.freeze({ type: 'number', minimum: 0, maximum: 1, defaultValue: 0.5 }),
  sunsetbotProviderEnabled: Object.freeze({ type: 'boolean', defaultValue: true }),
  skyOpportunityCardEnabled: Object.freeze({ type: 'boolean', defaultValue: true }),
  skyOpportunityMapEnabled: Object.freeze({ type: 'boolean', defaultValue: false }),
  skyOpportunityTomorrowSunsetEnabled: Object.freeze({ type: 'boolean', defaultValue: false }),
  sunsetbotTimeoutMs: Object.freeze({ type: 'integer', minimum: 2_000, maximum: 30_000, defaultValue: 12_000 }),
  sunsetbotMaxAttempts: Object.freeze({ type: 'integer', minimum: 1, maximum: 2, defaultValue: 2 }),
  sunsetbotRetryDelayMs: Object.freeze({ type: 'integer', minimum: 100, maximum: 5_000, defaultValue: 500 }),
  sunsetbotFreshTtlSeconds: Object.freeze({ type: 'integer', minimum: 300, maximum: 21_600, defaultValue: 5_400 }),
  sunsetbotStaleTtlSeconds: Object.freeze({ type: 'integer', minimum: 5_400, maximum: 43_200, defaultValue: 21_600 }),
  sunsetbotMaxGlobalConcurrency: Object.freeze({ type: 'integer', minimum: 1, maximum: 8, defaultValue: 4 }),
  sunsetbotMaxCityConcurrency: Object.freeze({ type: 'integer', minimum: 1, maximum: 4, defaultValue: 2 }),
  sunsetbotCircuitFailureThreshold: Object.freeze({ type: 'integer', minimum: 2, maximum: 20, defaultValue: 5 }),
  sunsetbotCircuitRollingWindowSeconds: Object.freeze({ type: 'integer', minimum: 60, maximum: 3_600, defaultValue: 600 }),
  sunsetbotCircuitFailureRateThreshold: Object.freeze({ type: 'number', minimum: .1, maximum: 1, defaultValue: .60 }),
  sunsetbotCircuitOpenSeconds: Object.freeze({ type: 'integer', minimum: 60, maximum: 3_600, defaultValue: 900 }),
  skyOpportunityDisplayThreshold: Object.freeze({ type: 'number', minimum: 0, maximum: 2.5, defaultValue: .20 }),
  skyOpportunityPaperThreshold: Object.freeze({ type: 'number', minimum: 0, maximum: 2.5, defaultValue: .60 }),
  sevenTimerProviderEnabled: Object.freeze({ type: 'boolean', defaultValue: true }),
  sevenTimerTimeoutMs: Object.freeze({ type: 'integer', minimum: 2_000, maximum: 30_000, defaultValue: 12_000 }),
  sevenTimerMaxAttempts: Object.freeze({ type: 'integer', minimum: 1, maximum: 2, defaultValue: 2 }),
  sevenTimerRetryDelayMs: Object.freeze({ type: 'integer', minimum: 100, maximum: 5_000, defaultValue: 500 }),
  sevenTimerAstroFreshTtlSeconds: Object.freeze({ type: 'integer', minimum: 1_800, maximum: 21_600, defaultValue: 10_800 }),
  sevenTimerMeteoFreshTtlSeconds: Object.freeze({ type: 'integer', minimum: 1_800, maximum: 21_600, defaultValue: 10_800 }),
  sevenTimerTwoFreshTtlSeconds: Object.freeze({ type: 'integer', minimum: 3_600, maximum: 43_200, defaultValue: 21_600 }),
  sevenTimerStaleTtlSeconds: Object.freeze({ type: 'integer', minimum: 10_800, maximum: 86_400, defaultValue: 43_200 }),
  sevenTimerAdminTestTimeoutMs: Object.freeze({ type: 'integer', minimum: 2_000, maximum: 15_000, defaultValue: 8_000 }),
  sevenTimerAdminTestCooldownSeconds: Object.freeze({ type: 'integer', minimum: 3, maximum: 300, defaultValue: 10 }),
  sevenTimerAdminTestMaxConcurrency: Object.freeze({ type: 'integer', minimum: 1, maximum: 3, defaultValue: 1 }),
  debugLogging: Object.freeze({ type: 'boolean', defaultValue: false }),
});

export const defaultRuntimeSettings = Object.freeze(Object.fromEntries(
  Object.entries(definitions).map(([name, definition]) => [name, definition.defaultValue]),
));

function validateValue(name, value, definition) {
  if (definition.type === 'boolean') {
    if (typeof value !== 'boolean') {
      throw new TypeError(`${name} must be a boolean`);
    }
    return value;
  }

  const validNumber = typeof value === 'number' && Number.isFinite(value);
  const validInteger = definition.type !== 'integer' || Number.isInteger(value);
  if (!validNumber || !validInteger ||
      value < definition.minimum || value > definition.maximum) {
    const kind = definition.type === 'integer' ? 'an integer' : 'a number';
    throw new RangeError(
      `${name} must be ${kind} between ${definition.minimum} and ${definition.maximum}`,
    );
  }
  return value;
}

// A setting dropped from `definitions` can still sit in configuration saved by
// an older release. Reading must not fail over dead data, so the persisted view
// is pruned first; writes through the admin API stay strict on unknown keys.
export function pruneUnknownRuntimeSettings(input) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) return input;
  return Object.fromEntries(
    Object.entries(input).filter(([name]) => Object.hasOwn(definitions, name)),
  );
}

export function validateRuntimeSettings(input = {}, { partial = false } = {}) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) {
    throw new TypeError('Runtime settings must be an object');
  }

  for (const name of Object.keys(input)) {
    if (!Object.hasOwn(definitions, name)) {
      throw new TypeError(`Unknown runtime setting: ${name}`);
    }
  }

  const result = partial ? {} : { ...defaultRuntimeSettings };
  for (const [name, value] of Object.entries(input)) {
    result[name] = validateValue(name, value, definitions[name]);
  }
  if (!partial) {
    if (result.sunsetbotStaleTtlSeconds < result.sunsetbotFreshTtlSeconds) {
      throw new RangeError('sunsetbotStaleTtlSeconds must not be below the fresh TTL');
    }
    if (result.sunsetbotMaxCityConcurrency > result.sunsetbotMaxGlobalConcurrency) {
      throw new RangeError('sunsetbotMaxCityConcurrency must not exceed global concurrency');
    }
    if (result.skyOpportunityPaperThreshold < result.skyOpportunityDisplayThreshold) {
      throw new RangeError('sky opportunity thresholds must remain ordered');
    }
    const maximumSevenTimerFreshTtl = Math.max(
      result.sevenTimerAstroFreshTtlSeconds,
      result.sevenTimerMeteoFreshTtlSeconds,
      result.sevenTimerTwoFreshTtlSeconds,
    );
    if (result.sevenTimerStaleTtlSeconds < maximumSevenTimerFreshTtl) {
      throw new RangeError('sevenTimerStaleTtlSeconds must not be below a fresh TTL');
    }
  }
  return Object.freeze(result);
}
