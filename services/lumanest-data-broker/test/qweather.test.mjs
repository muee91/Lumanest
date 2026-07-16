import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { authoritativeWeather } from '../src/context/qweather.mjs';
import { MemoryWeatherCache } from '../src/context/weather-cache.mjs';

const { privateKey } = generateKeyPairSync('ed25519');
const coordinate = { latitude: 30.25, longitude: 120.15 };

function response(path) {
  const bodies = {
    '/v7/weather/now': { code: '200', now: {
      obsTime: '2026-07-14T10:00:00+08:00', temp: '26', icon: '302', windSpeed: '18',
      wind360: '90', vis: '20', precip: '1.5', cloud: '80',
    } },
    '/v7/weather/24h': { code: '200', hourly: [
      { fxTime: '2026-07-14T11:00:00+08:00', icon: '302', windSpeed: '54' },
    ] },
    '/v7/minutely/5m': { code: '200', minutely: [
      { fxTime: '2026-07-14T10:05:00+08:00', precip: '2.5' },
      { fxTime: '2026-07-14T10:10:00+08:00', precip: '3' },
    ] },
    '/v7/warning/now': { code: '200', warning: [{
      id: 'official-1', pubTime: '2026-07-14T09:55:00+08:00',
      endTime: '2026-07-14T12:00:00+08:00', level: 'Red', status: 'active',
      title: '雷电红色预警', typeName: '雷电', text: '预计未来两小时局地有强雷电活动。',
    }] },
    '/v7/air/now': { code: '200', updateTime: '2026-07-14T10:00:00+08:00', now: {
      pubTime: '2026-07-14T10:00:00+08:00', aqi: '168', category: '中度污染',
      primary: 'PM2.5',
    } },
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
    '/v7/air/now', '/v7/minutely/5m', '/v7/warning/now', '/v7/weather/24h', '/v7/weather/now',
  ]);
  assert.equal(first.body.weather.thunder, true);
  assert.equal(first.body.forecast.nextHourPrecipitationMm, 5.5);
  assert.equal(first.body.forecast.nextThreeHoursMaxWindSpeedMps, 15);
  assert.equal(first.body.forecast.thunderNextThreeHours, true);
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
    fetcher: async (url) => url.pathname === '/v7/air/now'
      ? new Response(JSON.stringify({ code: '500' }), { status: 503 })
      : response(url.pathname),
  });

  assert.equal(result.ok, true);
  assert.equal(result.body.weather.airQualityIndex, null);
  assert.equal(result.body.weather.airQualityStale, true);
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
