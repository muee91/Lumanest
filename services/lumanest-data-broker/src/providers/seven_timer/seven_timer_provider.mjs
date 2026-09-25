import { apiErrorCodes } from '../../api/error-codes.mjs';

import { createHash, randomUUID } from 'node:crypto';

import { MemorySevenTimerCache } from '../../infrastructure/cache/seven_timer_cache.mjs';
import { SevenTimerCircuitBreaker } from '../../infrastructure/circuit_breaker/seven_timer_circuit_breaker.mjs';
import { MemorySevenTimerDiagnosticsStore } from '../../infrastructure/diagnostics/seven_timer_diagnostics_store.mjs';
import { SevenTimerMetrics } from '../../infrastructure/metrics/seven_timer_metrics.mjs';
import { SevenTimerClient } from './seven_timer_client.mjs';
import { freshTtlForProduct, sevenTimerConfig } from './seven_timer_config.mjs';
import { parseSevenTimerResponse } from './seven_timer_parser.mjs';

const requestKeys = new Set(['latitude', 'longitude', 'product']);
const products = new Set(['astro', 'meteo', 'two']);

export function validSevenTimerRequest(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== requestKeys.size ||
      !Object.keys(value).every((key) => requestKeys.has(key))) return null;
  const { latitude, longitude, product } = value;
  if (typeof latitude !== 'number' || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      typeof longitude !== 'number' || !Number.isFinite(longitude) || longitude < -180 || longitude > 180 ||
      !products.has(product)) return null;
  return { latitude, longitude, product };
}

function cacheKey({ latitude, longitude, product }) {
  const cell = `${latitude.toFixed(2)},${longitude.toFixed(2)}`;
  const coordinateHash = createHash('sha256').update(cell).digest('hex').slice(0, 24);
  return `${product}:${coordinateHash}`;
}

function publicValue(value, { cacheStatus, isStaleCache }) {
  return { ...structuredClone(value), cacheStatus, isStaleCache };
}

export class SevenTimerService {
  constructor({
    settings = () => ({}),
    baseUrl,
    cache = new MemorySevenTimerCache(),
    fetcher = fetch,
    now = () => new Date(),
    clientFactory,
    circuitBreakerFactory = () => new SevenTimerCircuitBreaker(),
    diagnosticsStore = new MemorySevenTimerDiagnosticsStore(),
    metrics = new SevenTimerMetrics(),
    logger = () => {},
  } = {}) {
    this.settings = settings;
    this.baseUrl = baseUrl;
    this.cache = cache;
    this.fetcher = fetcher;
    this.now = now;
    this.clientFactory = clientFactory;
    this.circuitBreakers = new Map([...products].map((product) => [product, circuitBreakerFactory(product)]));
    this.diagnosticsStore = diagnosticsStore;
    this.metrics = metrics;
    this.logger = logger;
    this.inFlight = new Map();
    this.testInFlight = new Map();
    this.lastTestAt = new Map();
    this.persistencePending = false;
    this.persistence = { ...diagnosticsStore.status(), lastSavedAt: null, lastErrorAt: null };
    this.diagnostics = new Map([...products].map((product) => [product, {
      product, status: 'unknown', lastAttemptAt: null, lastSuccessAt: null,
      lastFailureAt: null, lastErrorCode: null, traceId: null, sourceInitAt: null,
      sourceStatus: null, cacheStatus: 'unknown', pointCount: 0, circuitState: 'closed',
      lastLatencyMs: null, lastSuccessLatencyMs: null, lastFailureLatencyMs: null,
      lastAttempts: 0,
    }]));
  }

  async initialize() {
    const restored = await this.diagnosticsStore.load();
    if (restored?.products == null || !Array.isArray(restored.products)) return;
    this.persistence = { ...this.diagnosticsStore.status(), lastSavedAt: restored.savedAt ?? null, lastErrorAt: null };
    const allowed = new Set([
      'product', 'status', 'lastAttemptAt', 'lastSuccessAt', 'lastFailureAt', 'lastErrorCode',
      'traceId', 'sourceInitAt', 'sourceStatus', 'cacheStatus', 'pointCount', 'circuitState',
      'lastLatencyMs', 'lastSuccessLatencyMs', 'lastFailureLatencyMs', 'lastAttempts',
    ]);
    for (const entry of restored.products) {
      if (!products.has(entry?.product) || Object.keys(entry).some((name) => !allowed.has(name))) continue;
      this.diagnostics.set(entry.product, Object.freeze({ ...this.diagnostics.get(entry.product), ...entry }));
    }
  }

  _persist(product) {
    if (this.persistencePending) return;
    this.persistencePending = true;
    queueMicrotask(async () => {
      this.persistencePending = false;
      try {
        await this.diagnosticsStore.save({ version: 1, savedAt: this.now().toISOString(), products: [...this.diagnostics.values()] });
        this.persistence = { ...this.diagnosticsStore.status(), lastSavedAt: this.now().toISOString(), lastErrorAt: null };
      } catch {
        this.metrics.increment(product, 'diagnosticsPersistFailure');
        this.persistence = { ...this.diagnosticsStore.status(), lastSavedAt: this.persistence.lastSavedAt, lastErrorAt: this.now().toISOString() };
      }
    });
  }

  _record(product, patch) {
    const current = this.diagnostics.get(product);
    this.diagnostics.set(product, Object.freeze({ ...current, ...patch }));
    this._persist(product);
  }

  _log(entry) {
    try { this.logger(Object.freeze({ event: 'seven_timer_request', ...entry })); } catch { /* diagnostics must never break forecasts */ }
  }

  healthSnapshot() {
    const config = sevenTimerConfig(this.settings(), { baseUrl: this.baseUrl });
    const now = this.now();
    const productsSnapshot = [...products].map((product) => ({
      ...this.diagnostics.get(product),
      circuitState: this.circuitBreakers.get(product).state(now),
      sourceAgeMinutes: this.diagnostics.get(product).sourceInitAt == null ? null
        : Math.max(0, Math.round((now.getTime() - Date.parse(this.diagnostics.get(product).sourceInitAt)) / 60_000)),
    }));
    const statuses = productsSnapshot.map((entry) => entry.status);
    const status = !config.enabled ? 'disabled'
      : statuses.every((value) => value === 'healthy') ? 'healthy'
        : statuses.some((value) => value === 'healthy' || value === 'degraded') ? 'degraded'
          : statuses.some((value) => value === 'unavailable') ? 'unavailable' : 'unknown';
    return { provider: '7timer', enabled: config.enabled, status, checkedAt: now.toISOString(), cacheBackend: this.cache.status?.() ?? { mode: 'unknown', available: false, durable: false }, persistence: { ...this.persistence }, metrics: this.metrics.snapshot(), products: productsSnapshot };
  }

  async testProduct(query) {
    const valid = validSevenTimerRequest(query);
    if (valid == null) return { ok: false, error: apiErrorCodes.invalidRequest };
    const config = sevenTimerConfig(this.settings(), { baseUrl: this.baseUrl });
    const instant = this.now();
    const previous = this.lastTestAt.get(valid.product);
    if (this.testInFlight.has(valid.product)) {
      const traceId = randomUUID();
      this.metrics.increment(valid.product, 'manualTestRejected');
      this._log({ traceId, product: valid.product, outcome: 'rejected', errorCode: 'test_in_progress', attempts: 0, latencyMs: 0, cacheStatus: 'test', circuitState: this.circuitBreakers.get(valid.product).state(instant), manual: true });
      return { ok: false, error: apiErrorCodes.testInProgress, traceId };
    }
    if (previous != null && instant.getTime() - previous < config.adminTestCooldownSeconds * 1_000) {
      const traceId = randomUUID();
      this.metrics.increment(valid.product, 'manualTestRejected');
      this._log({ traceId, product: valid.product, outcome: 'rejected', errorCode: 'test_cooldown', attempts: 0, latencyMs: 0, cacheStatus: 'test', circuitState: this.circuitBreakers.get(valid.product).state(instant), manual: true });
      return { ok: false, error: apiErrorCodes.testCooldown, traceId, retryAfterSeconds: Math.ceil((config.adminTestCooldownSeconds * 1_000 - (instant.getTime() - previous)) / 1_000) };
    }
    if (this.testInFlight.size >= config.adminTestMaxConcurrency) {
      const traceId = randomUUID();
      this.metrics.increment(valid.product, 'manualTestRejected');
      this._log({ traceId, product: valid.product, outcome: 'rejected', errorCode: 'test_busy', attempts: 0, latencyMs: 0, cacheStatus: 'test', circuitState: this.circuitBreakers.get(valid.product).state(instant), manual: true });
      return { ok: false, error: apiErrorCodes.testBusy, traceId };
    }
    this.metrics.increment(valid.product, 'manualTestTotal');
    const operation = this._fetchLive(valid, {
      bypassCache: true,
      manual: true,
      configOverride: { timeoutMs: config.adminTestTimeoutMs, maxAttempts: 1 },
    }).finally(() => {
      this.testInFlight.delete(valid.product);
      this.lastTestAt.set(valid.product, this.now().getTime());
    });
    this.testInFlight.set(valid.product, operation);
    return operation;
  }

  async _fetchLive(query, { bypassCache = false, cached = { status: 'miss', entry: null }, manual = false, configOverride = {} } = {}) {
    const config = Object.freeze({ ...sevenTimerConfig(this.settings(), { baseUrl: this.baseUrl }), ...configOverride });
    const instant = this.now();
    const traceId = randomUUID();
    const startedAt = performance.now();
    const breaker = this.circuitBreakers.get(query.product);
    if (!config.enabled) {
      this._record(query.product, { status: 'disabled', lastAttemptAt: instant.toISOString(), lastFailureAt: instant.toISOString(), lastErrorCode: 'disabled', traceId, cacheStatus: 'disabled', circuitState: breaker.state(instant) });
      return { ok: false, error: apiErrorCodes.disabled, traceId };
    }
    this.metrics.increment(query.product, 'requestTotal');
    this.metrics.begin(query.product);
    this._record(query.product, { status: 'degraded', lastAttemptAt: instant.toISOString(), traceId, circuitState: breaker.state(instant) });
    if (!breaker.allow(instant)) {
      const latencyMs = Math.round(performance.now() - startedAt);
      this.metrics.increment(query.product, 'requestFailure');
      this.metrics.increment(query.product, 'circuitOpen');
      this.metrics.end(query.product, latencyMs);
      this._record(query.product, { status: 'unavailable', lastFailureAt: instant.toISOString(), lastErrorCode: 'circuit_open', cacheStatus: cached.status, circuitState: 'open' });
      this._log({ traceId, product: query.product, outcome: 'failure', errorCode: 'circuit_open', attempts: 0, latencyMs, cacheStatus: cached.status, circuitState: 'open', manual });
      if (!bypassCache && cached.status === 'stale') return { ok: true, body: publicValue(cached.entry.value, { cacheStatus: 'stale', isStaleCache: true }), traceId };
      return { ok: false, error: apiErrorCodes.unavailable, traceId };
    }
    let response;
    try {
      const client = this.clientFactory?.(config) ?? new SevenTimerClient({ config, fetcher: this.fetcher });
      response = await client.fetch(query);
    } catch {
      response = { ok: false, error: apiErrorCodes.upstreamError, attempts: 0 };
    }
    if (response.ok) {
      const parsed = parseSevenTimerResponse(response.body, { product: query.product, now: instant });
      if (parsed.ok) {
        breaker.success();
        const latencyMs = Math.round(performance.now() - startedAt);
        const value = { ...parsed.value, fetchedAt: instant.toISOString() };
        if (!bypassCache) await this.cache.set(cacheKey(query), value, { now: instant, freshTtlSeconds: freshTtlForProduct(config, query.product), staleTtlSeconds: config.staleTtlSeconds });
        this.metrics.increment(query.product, 'requestSuccess');
        this.metrics.end(query.product, latencyMs);
        this._record(query.product, { status: 'healthy', lastSuccessAt: instant.toISOString(), lastErrorCode: null, sourceInitAt: value.sourceInitAt, sourceStatus: value.sourceStatus, cacheStatus: bypassCache ? 'test' : 'miss', pointCount: value.points.length, circuitState: 'closed', lastLatencyMs: latencyMs, lastSuccessLatencyMs: latencyMs, lastAttempts: response.attempts ?? 1 });
        this._log({ traceId, product: query.product, outcome: 'success', errorCode: null, attempts: response.attempts ?? 1, latencyMs, cacheStatus: bypassCache ? 'test' : 'miss', circuitState: 'closed', manual });
        return { ok: true, body: publicValue(value, { cacheStatus: bypassCache ? 'test' : 'miss', isStaleCache: false }), traceId };
      }
      response.error = parsed.error;
    }
    breaker.failure(instant);
    const latencyMs = Math.round(performance.now() - startedAt);
    const failureCode = response.error ?? 'upstream_error';
    this.metrics.increment(query.product, 'requestFailure');
    this.metrics.end(query.product, latencyMs);
    if (!bypassCache && cached.status === 'stale') this.metrics.increment(query.product, 'staleFallback');
    this._record(query.product, { status: cached.status === 'stale' && !bypassCache ? 'degraded' : 'unavailable', lastFailureAt: instant.toISOString(), lastErrorCode: failureCode, cacheStatus: cached.status, circuitState: breaker.state(instant), lastLatencyMs: latencyMs, lastFailureLatencyMs: latencyMs, lastAttempts: response.attempts ?? config.maxAttempts });
    this._log({ traceId, product: query.product, outcome: cached.status === 'stale' && !bypassCache ? 'stale_fallback' : 'failure', errorCode: failureCode, attempts: response.attempts ?? config.maxAttempts, latencyMs, cacheStatus: cached.status, circuitState: breaker.state(instant), manual });
    if (!bypassCache && cached.status === 'stale') return { ok: true, body: publicValue(cached.entry.value, { cacheStatus: 'stale', isStaleCache: true }), traceId };
    return { ok: false, error: apiErrorCodes.unavailable, traceId };
  }

  async forecast(query) {
    const config = sevenTimerConfig(this.settings(), { baseUrl: this.baseUrl });
    if (!config.enabled) {
      this._record(query.product, { status: 'disabled', lastErrorCode: 'disabled', cacheStatus: 'disabled', circuitState: this.circuitBreakers.get(query.product).state(this.now()) });
      return { ok: false, error: apiErrorCodes.disabled };
    }
    const key = cacheKey(query);
    const instant = this.now();
    const cached = await this.cache.get(key, instant);
    if (cached.status === 'hit') {
      this.metrics.increment(query.product, 'cacheHit');
      this._record(query.product, { status: 'healthy', cacheStatus: 'hit', pointCount: cached.entry.value.points?.length ?? 0, sourceInitAt: cached.entry.value.sourceInitAt ?? null, sourceStatus: cached.entry.value.sourceStatus ?? null, circuitState: this.circuitBreakers.get(query.product).state(instant) });
      return { ok: true, body: publicValue(cached.entry.value, {
        cacheStatus: 'hit', isStaleCache: false,
      }) };
    }
    if (this.inFlight.has(key)) return this.inFlight.get(key);
    const operation = (async () => {
      return this._fetchLive(query, { cached });
    })().finally(() => this.inFlight.delete(key));
    this.inFlight.set(key, operation);
    return operation;
  }
}
