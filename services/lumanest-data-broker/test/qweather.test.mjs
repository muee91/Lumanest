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
    '/v7/minutely/5m', '/v7/warning/now', '/v7/weather/24h', '/v7/weather/now',
  ]);
  assert.equal(first.body.weather.thunder, true);
  assert.equal(first.body.forecast.nextHourPrecipitationMm, 5.5);
  assert.equal(first.body.forecast.nextThreeHoursMaxWindSpeedMps, 15);
  assert.equal(first.body.forecast.thunderNextThreeHours, true);
  assert.equal(first.body.officialWarnings[0].severity, 'critical');

  const second = await authoritativeWeather({ ...options, fetcher: async () => {
    throw new Error('fresh cache must avoid the network');
  } });
  assert.equal(second.ok, true);
  assert.equal(second.cache, 'fresh');
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
