import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { authoritativeWeather } from '../src/context/qweather.mjs';
import { MemoryWeatherCache } from '../src/context/weather-cache.mjs';

const { privateKey } = generateKeyPairSync('ed25519');
const coordinate = { latitude: 30.25, longitude: 120.15 };

function response(path) {
  const bodies = {
    '/weather/v1/current/30.25/120.15': {
      updateTime: '2026-07-14T10:00:00+08:00',
      condition: { code: '302' },
      temperature: { value: 26 },
      wind: { direction: { degree: 90 }, speed: { value: 5 } },
      visibility: { value: 20_000 },
      precipitation: { amount: { value: 1.5 } },
      cloudCover: 0.8,
    },
    '/weather/v1/hourly/30.25/120.15': { hours: [
      {
        forecastTime: '2026-07-14T03:00:00Z', condition: { code: '302' },
        wind: { speed: { value: 15 } }, visibility: { value: 18_000 },
      },
    ] },
    '/v7/minutely/5m': { code: '200', minutely: [
      { fxTime: '2026-07-14T10:05:00+08:00', precip: '2.5' },
      { fxTime: '2026-07-14T10:10:00+08:00', precip: '3' },
    ] },
    '/weatheralert/v1/current/30.25/120.15': { alerts: [{
      id: 'official-1', issuedTime: '2026-07-14T09:55:00+08:00',
      expireTime: '2026-07-14T12:00:00+08:00', severity: 'extreme',
      eventType: { name: '雷电' }, headline: '雷电红色预警',
      description: '预计未来两小时局地有强雷电活动。',
      instruction: '远离制高点、水边、孤立树木和金属设备。',
    }] },
    '/airquality/v1/current/30.25/120.15': { indexes: [{
      code: 'cn', aqi: 168, category: '中度污染', primaryPollutant: { name: 'PM2.5' },
    }] },
  };
  return new Response(JSON.stringify(bodies[path]), { status: 200 });
}

test('authoritative weather normalizes all licensed QWeather sources and caches by opaque cell', async () => {
  const cache = new MemoryWeatherCache();
  const paths = [];
  const options = {
    coordinate,
    apiHost: 'https://project.qweatherapi.com',
    privateKey,
    keyId: 'key-id',
    projectId: 'project-id',
    cache,
    now: () => new Date('2026-07-14T02:02:00Z'),
    fetcher: async (url, request) => {
      paths.push(url.pathname);
      assert.match(request.headers.Authorization, /^Bearer [^.]+\.[^.]+\.[^.]+$/);
      return response(url.pathname);
    },
  };
  const first = await authoritativeWeather(options);
  assert.equal(first.ok, true);
  assert.equal(first.cache, 'miss');
  assert.deepEqual(paths.sort(), [
    '/airquality/v1/current/30.25/120.15', '/v7/minutely/5m',
    '/weather/v1/current/30.25/120.15', '/weather/v1/hourly/30.25/120.15',
    '/weatheralert/v1/current/30.25/120.15',
  ]);
  assert.equal(first.body.weather.thunder, true);
  assert.equal(first.body.forecast.nextHourPrecipitationMm, 5.5);
  assert.equal(first.body.forecast.nextThreeHoursMaxWindSpeedMps, 15);
  assert.equal(first.body.forecast.thunderNextThreeHours, true);
  assert.equal(first.body.forecast.hourly[0].visibilityKm, 18);
  assert.equal(first.body.officialWarnings[0].severity, 'critical');
  assert.equal(first.body.officialWarnings[0].title, '雷电红色预警');
  assert.equal(first.body.officialWarnings[0].description, '预计未来两小时局地有强雷电活动。');
  assert.deepEqual(first.body.officialWarnings[0].guidance, [
    '远离制高点、水边、孤立树木和金属设备。',
    '关注当地气象部门的最新预警和现场管制信息。',
  ]);
  assert.equal(first.body.weather.airQualityIndex, 168);
  assert.equal(first.body.weather.airQualityCategory, '中度污染');
  assert.equal(first.body.weather.primaryPollutant, 'PM2.5');
  assert.equal(first.body.weather.airQualityStale, false);

  const second = await authoritativeWeather({ ...options, fetcher: async () => {
    throw new Error('fresh cache must avoid the network');
  } });
  assert.equal(second.ok, true);
  assert.equal(second.cache, 'fresh');
});

test('air quality failure never breaks authoritative weather', async () => {
  const result = await authoritativeWeather({
    coordinate,
    apiHost: 'https://project.qweatherapi.com',
    privateKey,
    keyId: 'key-id',
    projectId: 'project-id',
    cache: new MemoryWeatherCache(),
    now: () => new Date('2026-07-14T02:02:00Z'),
    fetcher: async (url) => url.pathname === '/airquality/v1/current/30.25/120.15'
      ? new Response(JSON.stringify({ code: '500' }), { status: 503 })
      : response(url.pathname),
  });

  assert.equal(result.ok, true);
  assert.equal(result.body.weather.airQualityIndex, null);
  assert.equal(result.body.weather.airQualityStale, true);
});

test('three-hour aggregates ignore later entries while retaining 24-hour coverage', async () => {
  const hourly = Array.from({ length: 24 }, (_, index) => ({
    fxTime: new Date(Date.UTC(2026, 6, 14, 3 + index)).toISOString(),
    icon: index === 3 ? '302' : '101',
    windSpeed: index === 3 ? '540' : String((index + 1) * 3.6),
    precip: '0',
    vis: '20',
  }));
  const result = await authoritativeWeather({
    coordinate,
    apiHost: 'https://project.qweatherapi.com',
    privateKey,
    keyId: 'key-id',
    projectId: 'project-id',
    cache: new MemoryWeatherCache(),
    now: () => new Date('2026-07-14T02:02:00Z'),
      fetcher: async (url) => url.pathname === '/weather/v1/hourly/30.25/120.15'
      ? new Response(JSON.stringify({ code: '200', hourly }), { status: 200 })
      : response(url.pathname),
  });

  assert.equal(result.ok, true);
  assert.equal(result.body.forecast.hourly.length, 24);
  assert.equal(result.body.forecast.nextThreeHoursMaxWindSpeedMps, 3);
  assert.equal(result.body.forecast.thunderNextThreeHours, false);
  assert.equal(result.body.forecast.hourly[3].thunder, true);
});

test('authoritative weather uses a bounded stale cache and rejects arbitrary hosts', async () => {
  const cache = new MemoryWeatherCache();
  const base = {
    coordinate,
    apiHost: 'https://project.qweatherapi.com',
    privateKey,
    keyId: 'key-id',
    projectId: 'project-id',
    cache,
    fetcher: async (url) => response(url.pathname),
    now: () => new Date('2026-07-14T02:02:00Z'),
  };
  await authoritativeWeather(base);
  const stale = await authoritativeWeather({
    ...base,
    now: () => new Date('2026-07-14T02:08:00Z'),
    fetcher: async () => { throw new Error('offline'); },
  });
  assert.equal(stale.ok, true);
  assert.equal(stale.cache, 'stale');
  assert.equal(stale.body.weather.stale, true);

  const invalid = await authoritativeWeather({ ...base, apiHost: 'https://attacker.example' });
  assert.deepEqual(invalid, { ok: false, error: 'not_configured' });
});

test('a routine upstream lag does not mark fresh weather as stale', async () => {
  // `/v7/weather/now` refreshes about every 15 minutes, so a healthy reading is
  // often 20-40 minutes old. Treating that as stale made every context snapshot
  // stale and forced the assistant to reject it with `snapshot_expired`.
  const options = {
    coordinate,
    apiHost: 'https://project.qweatherapi.com',
    privateKey,
    keyId: 'key-id',
    projectId: 'project-id',
    cache: new MemoryWeatherCache(),
    fetcher: async (url) => response(url.pathname),
  };

  // obsTime is 02:00Z; 40 minutes of lag is ordinary, not degraded.
  const lagging = await authoritativeWeather({
    ...options,
    now: () => new Date('2026-07-14T02:40:00Z'),
  });
  assert.equal(lagging.ok, true);
  assert.equal(lagging.body.weather.stale, false);

  // An hour-plus-old reading is genuinely stale and must stay flagged.
  const old = await authoritativeWeather({
    ...options,
    cache: new MemoryWeatherCache(),
    now: () => new Date('2026-07-14T03:20:00Z'),
  });
  assert.equal(old.ok, true);
  assert.equal(old.body.weather.stale, true);
});

test('incomplete warning cache refreshes online and degrades safely offline', async () => {
  const cache = new RecordingCache();
  const base = {
    coordinate,
    apiHost: 'https://project.qweatherapi.com',
    privateKey,
    keyId: 'key-id',
    projectId: 'project-id',
    cache,
    now: () => new Date('2026-07-14T02:02:00Z'),
    fetcher: async (url) => response(url.pathname),
  };
  await authoritativeWeather(base);
  delete cache.entry.body.officialWarnings[0].title;
  delete cache.entry.body.officialWarnings[0].description;
  delete cache.entry.body.officialWarnings[0].guidance;

  const refreshed = await authoritativeWeather(base);
  assert.equal(refreshed.cache, 'miss');
  assert.equal(refreshed.body.officialWarnings[0].title, '雷电红色预警');

  delete cache.entry.body.officialWarnings[0].title;
  const stale = await authoritativeWeather({
    ...base,
    now: () => new Date('2026-07-14T02:08:00Z'),
    fetcher: async () => { throw new Error('offline'); },
  });
  assert.equal(stale.cache, 'stale');
  assert.equal(stale.body.officialWarnings[0].title, '官方气象预警');
});

class RecordingCache {
  entry = null;

  async get() {
    return this.entry;
  }

  async set(_key, value) {
    this.entry = structuredClone(value);
  }
}
