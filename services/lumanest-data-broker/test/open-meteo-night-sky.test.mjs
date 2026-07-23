import assert from 'node:assert/strict';
import test from 'node:test';

import { OpenMeteoNightSkyForecast } from '../src/environment/open-meteo-night-sky.mjs';

function payload() {
  const time = ['2026-07-23T15:00', '2026-07-23T16:00', '2026-07-23T17:00'];
  return {
    hourly: {
      time,
      cloud_cover: [10, 20, 30],
      cloud_cover_low: [1, 2, 3],
      cloud_cover_mid: [4, 5, 6],
      cloud_cover_high: [7, 8, 9],
      visibility: [30000, 25000, 20000],
      precipitation_probability: [0, 5, 10],
      precipitation: [0, 0, 0],
      relative_humidity_2m: [50, 55, 60],
      wind_speed_10m: [5, 6, 7],
      wind_gusts_10m: [10, 12, 14],
    },
  };
}

test('open meteo forecast validates hourly evidence and caches by coarse cell', async () => {
  let calls = 0;
  const service = new OpenMeteoNightSkyForecast({
    now: () => new Date('2026-07-23T15:15:00Z'),
    fetcher: async (url) => {
      calls += 1;
      assert.equal(url.pathname, '/v1/forecast');
      assert.match(url.searchParams.get('hourly'), /cloud_cover_low/);
      assert.equal(url.searchParams.get('timezone'), 'GMT');
      return new Response(JSON.stringify(payload()));
    },
  });
  const first = await service.forecast({ latitude: 30.2501, longitude: 120.1501, hours: 24 });
  const second = await service.forecast({ latitude: 30.2502, longitude: 120.1502, hours: 24 });
  assert.equal(first.ok, true);
  assert.equal(first.body.points.length, 3);
  assert.equal(first.body.points[1].visibilityMeters, 25000);
  assert.equal(first.body.cacheStatus, 'miss');
  assert.equal(second.body.cacheStatus, 'hit');
  assert.equal(calls, 1);
});

test('open meteo rejects malformed unequal hourly arrays', async () => {
  const broken = payload();
  broken.hourly.visibility = [1000];
  const service = new OpenMeteoNightSkyForecast({
    fetcher: async () => new Response(JSON.stringify(broken)),
  });
  const result = await service.forecast({ latitude: 30, longitude: 120, hours: 12 });
  assert.deepEqual(result, { ok: false, error: 'upstream_unavailable' });
});
