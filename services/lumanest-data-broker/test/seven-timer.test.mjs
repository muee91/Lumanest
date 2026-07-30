import assert from 'node:assert/strict';
import test from 'node:test';

import { MemorySevenTimerCache } from '../src/infrastructure/cache/seven_timer_cache.mjs';
import { SevenTimerCircuitBreaker } from '../src/infrastructure/circuit_breaker/seven_timer_circuit_breaker.mjs';
import { MemorySevenTimerDiagnosticsStore } from '../src/infrastructure/diagnostics/seven_timer_diagnostics_store.mjs';
import { SevenTimerClient } from '../src/providers/seven_timer/seven_timer_client.mjs';
import { sevenTimerConfig } from '../src/providers/seven_timer/seven_timer_config.mjs';
import { parseSevenTimerResponse } from '../src/providers/seven_timer/seven_timer_parser.mjs';
import { SevenTimerService, validSevenTimerRequest } from '../src/providers/seven_timer/seven_timer_provider.mjs';

const now = new Date('2026-07-19T06:00:00Z');

function json(body, { status = 200, contentType = 'application/json' } = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': contentType },
  });
}

function body(product, dataseries) {
  return { product, init: '2026071900', dataseries };
}

test('validates the exact public request shape', () => {
  assert.deepEqual(validSevenTimerRequest({ latitude: 30.2, longitude: 120.1, product: 'astro' }), {
    latitude: 30.2, longitude: 120.1, product: 'astro',
  });
  assert.equal(validSevenTimerRequest({ latitude: 91, longitude: 0, product: 'astro' }), null);
  assert.equal(validSevenTimerRequest({ latitude: 1, longitude: 2, product: 'civil' }), null);
  assert.equal(validSevenTimerRequest({ latitude: 1, longitude: 2, product: 'two', extra: true }), null);
});

test('parses ASTRO levels into ranges and skips a bad point', () => {
  const parsed = parseSevenTimerResponse(body('astro', [
    { timepoint: 'bad', cloudcover: 1 },
    {
      timepoint: 3, cloudcover: 3, seeing: 4, transparency: 3, rh2m: 11,
      wind10m: { direction: 'E', speed: 2 }, temp2m: 26, lifted_index: 2,
      prec_type: 'none', unknown: 'ignored',
    },
  ]), { product: 'astro', now });
  assert.equal(parsed.ok, true);
  assert.equal(parsed.value.points.length, 1);
  assert.deepEqual(parsed.value.points[0].cloudCover, {
    level: 3, min: 19, max: 31, unit: 'percent',
  });
  assert.deepEqual(parsed.value.points[0].seeing, {
    level: 4, min: 1, max: 1.25, unit: 'arcsec',
  });
  assert.equal(parsed.value.points[0].validAt, '2026-07-19T03:00:00.000Z');
  assert.equal('unknown' in parsed.value.points[0], false);
});

test('parses METEO profiles and preserves high-resolution wind ranges', () => {
  const parsed = parseSevenTimerResponse(body('meteo', [{
    timepoint: 6, cloudcover: 7, lowcloud: 4, midcloud: 2, highcloud: 8,
    rh_profile: [{ layer: '950mb', rh: 14 }, { layer: 'invalid', rh: 10 }],
    wind_profile: [{ layer: '500mb', direction: 215, speed: 10 }],
    msl_pressure: 1002, prec_type: 'rain', prec_amount: 3, snow_depth: 2,
  }]), { product: 'meteo', now });
  assert.equal(parsed.ok, true);
  assert.equal(parsed.value.points[0].humidityProfile.length, 1);
  assert.deepEqual(parsed.value.points[0].windProfile[0].speed, {
    level: 10, min: 41.4, max: 46.2, unit: 'mps',
  });
  assert.equal(parsed.value.points[0].precipitation.amount.unit, 'mm_per_hour');
  assert.equal(parsed.value.points[0].snowDepth.unit, 'cm');
});

test('parses TWO as a long-range trend and never trusts sentinel values', () => {
  const parsed = parseSevenTimerResponse(body('two', [{
    timepoint: 204, cloudcover: -9999, lifted_index: -1,
    temp2m: { min: '-9999', max: 29 }, rh2m: 13,
    wind10m: { direction: '-9999', speed: -9999 }, weather: 'clear',
  }]), { product: 'two', now });
  assert.equal(parsed.ok, true);
  const point = parsed.value.points[0];
  assert.equal(point.validAt, '2026-07-27T12:00:00.000Z');
  assert.equal(point.cloudCover, null);
  assert.equal(point.temperatureMinCelsius, null);
  assert.equal(point.temperatureMaxCelsius, 29);
  assert.equal(point.wind, null);
  assert.equal(point.weatherCode, 'clear');
});

test('rejects wrong products, invalid init and an empty valid series', () => {
  assert.equal(parseSevenTimerResponse(body('two', [{ timepoint: 1 }]), {
    product: 'astro', now,
  }).ok, false);
  assert.equal(parseSevenTimerResponse({ product: 'astro', init: 'bad', dataseries: [] }, {
    product: 'astro', now,
  }).error, 'invalid_init');
  assert.equal(parseSevenTimerResponse(body('astro', [{ timepoint: -1 }]), {
    product: 'astro', now,
  }).error, 'empty_dataseries');
});

test('client accepts bounded JSON compatibility responses and formats coordinates', async () => {
  let seen;
  const client = new SevenTimerClient({
    config: sevenTimerConfig({}, { baseUrl: 'https://www.7timer.info' }),
    fetcher: async (url) => {
      seen = url;
      return json(body('astro', [{ timepoint: 3 }]), { contentType: 'text/plain' });
    },
  });
  const result = await client.fetch({ latitude: 30.27449, longitude: 120.15549, product: 'astro' });
  assert.equal(result.ok, true);
  assert.equal(seen.searchParams.get('lat'), '30.274');
  assert.equal(seen.searchParams.get('lon'), '120.155');
  assert.equal(seen.searchParams.get('product'), 'astro');
});

test('client follows one product-specific allowlisted redirect and rejects unsafe redirects', async () => {
  for (const [product, path, contentType] of [
    ['astro', '/bin/astro.php', 'text/html; charset=UTF-8'],
    ['meteo', '/bin/meteo.php', 'text/plain'],
    ['two', '/bin/two.php', 'text/html; charset=UTF-8'],
  ]) {
    let calls = 0;
    const client = new SevenTimerClient({
      config: sevenTimerConfig({}),
      fetcher: async (url) => {
        calls += 1;
        if (calls === 1) {
          return new Response('', {
            status: 302,
            headers: { Location: `https://www.7timer.info${path}?output=json` },
          });
        }
        return json(body(product, [{ timepoint: 3 }]), { contentType });
      },
    });
    assert.equal((await client.fetch({ latitude: 1, longitude: 2, product })).ok, true);
    assert.equal(calls, 2);
  }

  const rejected = new SevenTimerClient({
    config: sevenTimerConfig({}),
    fetcher: async () => new Response('', {
      status: 302,
      headers: { Location: 'http://evil.example/data' },
    }),
  });
  assert.equal((await rejected.fetch({ latitude: 1, longitude: 2, product: 'meteo' })).error,
    'redirect_rejected');
});

test('client retries once and rejects oversized or non-JSON bodies', async () => {
  let calls = 0;
  const waits = [];
  const client = new SevenTimerClient({
    config: sevenTimerConfig({ sevenTimerRetryDelayMs: 500 }),
    sleep: async (value) => waits.push(value),
    jitter: () => 17,
    fetcher: async () => {
      calls += 1;
      return calls === 1
        ? json({}, { status: 503 })
        : json(body('astro', [{ timepoint: 3 }]));
    },
  });
  assert.equal((await client.fetch({ latitude: 1, longitude: 2, product: 'astro' })).ok, true);
  assert.deepEqual(waits, [517]);

  const html = new SevenTimerClient({
    config: sevenTimerConfig({ sevenTimerMaxAttempts: 1 }),
    fetcher: async () => new Response('<html>down</html>', {
      headers: { 'Content-Type': 'text/html' },
    }),
  });
  assert.equal((await html.fetch({ latitude: 1, longitude: 2, product: 'astro' })).error,
    'unexpected_content_type');

  const oversized = new SevenTimerClient({
    config: { ...sevenTimerConfig({ sevenTimerMaxAttempts: 1 }), maximumResponseBytes: 4 },
    fetcher: async () => new Response('{"x":1}', {
      headers: { 'Content-Type': 'application/json', 'Content-Length': '7' },
    }),
  });
  assert.equal((await oversized.fetch({ latitude: 1, longitude: 2, product: 'astro' })).error,
    'response_too_large');
});

test('service caches successes, coalesces requests and falls back to stale data', async () => {
  let instant = new Date('2026-07-19T06:00:00Z');
  let calls = 0;
  let available = true;
  const cache = new MemorySevenTimerCache();
  const service = new SevenTimerService({
    cache,
    now: () => instant,
    settings: () => ({
      sevenTimerAstroFreshTtlSeconds: 1_800,
      sevenTimerStaleTtlSeconds: 10_800,
    }),
    clientFactory: () => ({
      fetch: async () => {
        calls += 1;
        await new Promise((resolve) => setTimeout(resolve, 5));
        return available
          ? { ok: true, body: body('astro', [{ timepoint: 3, cloudcover: 1 }]) }
          : { ok: false, error: 'upstream_error' };
      },
    }),
  });
  const query = { latitude: 30.274, longitude: 120.155, product: 'astro' };
  const [first, concurrent] = await Promise.all([service.forecast(query), service.forecast(query)]);
  assert.equal(first.body.cacheStatus, 'miss');
  assert.equal(concurrent.body.cacheStatus, 'miss');
  assert.equal(calls, 1);
  assert.equal((await service.forecast(query)).body.cacheStatus, 'hit');
  assert.equal(calls, 1);

  instant = new Date(instant.getTime() + 2 * 3_600_000);
  available = false;
  const stale = await service.forecast(query);
  assert.equal(stale.ok, true);
  assert.equal(stale.body.cacheStatus, 'stale');
  assert.equal(stale.body.isStaleCache, true);

  instant = new Date(instant.getTime() + 3 * 3_600_000);
  assert.equal((await service.forecast(query)).ok, false);
});

test('disabled service never constructs a client', async () => {
  const service = new SevenTimerService({
    settings: () => ({ sevenTimerProviderEnabled: false }),
    clientFactory: () => { throw new Error('must not create client'); },
  });
  assert.deepEqual(await service.forecast({ latitude: 1, longitude: 2, product: 'astro' }), {
    ok: false, error: 'disabled',
  });
});

test('service diagnostics expose stable error codes and never retain coordinates', async () => {
  const service = new SevenTimerService({
    settings: () => ({}),
    clientFactory: () => ({ fetch: async () => ({ ok: false, error: 'timeout' }) }),
  });
  const result = await service.testProduct({ latitude: 31.23, longitude: 121.47, product: 'astro' });
  assert.equal(result.ok, false);
  assert.equal(typeof result.traceId, 'string');
  const snapshot = service.healthSnapshot();
  const astro = snapshot.products.find((entry) => entry.product === 'astro');
  assert.equal(astro.lastErrorCode, 'timeout');
  assert.equal(astro.traceId, result.traceId);
  assert.doesNotMatch(JSON.stringify(snapshot), /31\.23|121\.47/);
});

test('product circuit breakers are isolated and one product cannot block another', async () => {
  const service = new SevenTimerService({
    circuitBreakerFactory: () => new SevenTimerCircuitBreaker({ failureThreshold: 1, openSeconds: 1_800 }),
    clientFactory: () => ({ fetch: async ({ product }) => product === 'astro'
      ? { ok: false, error: 'timeout', attempts: 1 }
      : { ok: true, attempts: 1, body: body(product, [{ timepoint: 3, cloudcover: 1 }]) } }),
  });
  assert.equal((await service.forecast({ latitude: 1, longitude: 2, product: 'astro' })).ok, false);
  assert.equal((await service.forecast({ latitude: 1, longitude: 2, product: 'meteo' })).ok, true);
  const snapshot = service.healthSnapshot();
  assert.equal(snapshot.products.find((entry) => entry.product === 'astro').circuitState, 'open');
  assert.equal(snapshot.products.find((entry) => entry.product === 'meteo').circuitState, 'closed');
});

test('manual tests enforce independent timeout, concurrency and cooldown', async () => {
  let release;
  let receivedConfig;
  const service = new SevenTimerService({
    settings: () => ({ sevenTimerAdminTestTimeoutMs: 3_000, sevenTimerAdminTestCooldownSeconds: 30, sevenTimerAdminTestMaxConcurrency: 1 }),
    clientFactory: (config) => { receivedConfig = config; return { fetch: () => new Promise((resolve) => { release = () => resolve({ ok: false, error: 'timeout', attempts: 1 }); }) }; },
  });
  const query = { latitude: 1, longitude: 2, product: 'astro' };
  const active = service.testProduct(query);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(receivedConfig.timeoutMs, 3_000);
  assert.equal(receivedConfig.maxAttempts, 1);
  assert.equal((await service.testProduct(query)).error, 'test_in_progress');
  assert.equal((await service.testProduct({ ...query, product: 'meteo' })).error, 'test_busy');
  release();
  await active;
  assert.equal((await service.testProduct(query)).error, 'test_cooldown');
});

test('diagnostics persist across service restart and structured logs stay coordinate-free', async () => {
  const store = new MemorySevenTimerDiagnosticsStore();
  const logs = [];
  const first = new SevenTimerService({
    diagnosticsStore: store,
    logger: (entry) => logs.push(entry),
    clientFactory: () => ({ fetch: async () => ({ ok: false, error: 'unexpected_content_type', attempts: 2 }) }),
  });
  await first.forecast({ latitude: 31.23, longitude: 121.47, product: 'two' });
  await new Promise((resolve) => setImmediate(resolve));
  const second = new SevenTimerService({ diagnosticsStore: store });
  await second.initialize();
  const restored = second.healthSnapshot().products.find((entry) => entry.product === 'two');
  assert.equal(restored.lastErrorCode, 'unexpected_content_type');
  assert.equal(restored.lastAttempts, 2);
  assert.equal(logs[0].product, 'two');
  assert.equal(typeof logs[0].traceId, 'string');
  assert.doesNotMatch(JSON.stringify(logs), /31\.23|121\.47|api\.pl/);
});

test('circuit breaker opens after repeated provider failures and permits one probe', () => {
  const breaker = new SevenTimerCircuitBreaker({ failureThreshold: 3, openSeconds: 1_800 });
  const instant = new Date('2026-07-19T06:00:00Z');
  breaker.failure(instant);
  breaker.failure(instant);
  assert.equal(breaker.allow(instant), true);
  breaker.failure(instant);
  assert.equal(breaker.state(instant), 'open');
  assert.equal(breaker.allow(instant), false);
  const later = new Date(instant.getTime() + 1_801_000);
  assert.equal(breaker.allow(later), true);
  assert.equal(breaker.allow(later), false);
  breaker.success();
  assert.equal(breaker.state(later), 'closed');
});
