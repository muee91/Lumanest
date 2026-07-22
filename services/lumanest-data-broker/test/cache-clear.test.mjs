import assert from 'node:assert/strict';
import test from 'node:test';

import { MemoryWeatherCache } from '../src/context/weather-cache.mjs';
import { MemorySevenTimerCache } from '../src/infrastructure/cache/seven_timer_cache.mjs';
import { MemorySkyOpportunityCache } from '../src/infrastructure/cache/sky_opportunity_cache.mjs';


test('admin cache clear primitives remove every in-memory product cache', async () => {
  const now = new Date('2026-07-22T00:00:00Z');
  const weather = new MemoryWeatherCache();
  await weather.set('weather-key', { cachedAt: now.toISOString() });
  await weather.setSafetyDetails(
    'ctx_1234567890abcdef12345678',
    [{ eventId: 'warning' }],
    new Date(now.getTime() + 60_000).toISOString(),
  );

  const sky = new MemorySkyOpportunityCache();
  await sky.set('sky-key', { summary: {} }, {
    fetchedAt: now,
    freshTtlSeconds: 60,
    staleTtlSeconds: 120,
  });
  await sky.setCityCandidates('city-key', {
    requestedCity: '海宁',
    candidates: [{ latitude: 30.5, longitude: 120.7 }],
  }, { now, ttlSeconds: 60 });

  const sevenTimer = new MemorySevenTimerCache();
  await sevenTimer.set('seven-key', { points: [] }, {
    now,
    freshTtlSeconds: 60,
    staleTtlSeconds: 120,
  });

  await Promise.all([weather.clear(), sky.clear(), sevenTimer.clear()]);

  assert.equal(await weather.get('weather-key'), null);
  assert.equal(
    await weather.getSafetyDetail(
      'ctx_1234567890abcdef12345678',
      'warning',
      now,
    ),
    null,
  );
  assert.equal((await sky.get('sky-key', now)).status, 'miss');
  assert.equal((await sky.getCityCandidates('city-key', now)).status, 'miss');
  assert.equal((await sevenTimer.get('seven-key', now)).status, 'miss');
});
