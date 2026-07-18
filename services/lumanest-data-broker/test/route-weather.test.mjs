import assert from 'node:assert/strict';
import test from 'node:test';

import { routeWeatherForecast, validRouteWeatherRequest } from '../src/context/route-weather.mjs';

const now = new Date('2026-07-18T02:00:00Z');
const request = {
  routeId: 'r1234abcd',
  samples: [
    {
      latitude: 30.25, longitude: 120.15, system: 'wgs84', progress: 0,
      expectedAt: '2026-07-18T02:10:00Z',
    },
    {
      latitude: 30.5, longitude: 120.5, system: 'wgs84', progress: 1,
      expectedAt: '2026-07-18T03:10:00Z',
    },
  ],
};

test('route weather request accepts only bounded ordered WGS84 samples', () => {
  assert.equal(validRouteWeatherRequest(request, now), true);
  assert.equal(validRouteWeatherRequest({ ...request, extra: true }, now), false);
  assert.equal(validRouteWeatherRequest({
    ...request,
    samples: request.samples.map((sample) => ({ ...sample, system: 'gcj02' })),
  }, now), false);
  assert.equal(validRouteWeatherRequest({
    ...request,
    samples: [request.samples[1], request.samples[0]],
  }, now), false);
  assert.equal(validRouteWeatherRequest({
    ...request,
    samples: Array.from({ length: 6 }, (_, index) => ({
      ...request.samples[0], progress: index / 5,
    })),
  }, now), false);
});

test('route weather selects the closest hourly forecast without returning coordinates', async () => {
  const result = await routeWeatherForecast({
    body: request,
    now: () => now,
    fetchWeather: async (coordinate) => ({
      ok: true,
      cache: coordinate.latitude === 30.25 ? 'miss' : 'stale',
      body: { forecast: { hourly: [
        {
          at: '2026-07-18T02:00:00Z', condition: 'clear', cloudCoverPercent: 20,
          windSpeedMps: 1.5, precipitationMm: 0, visibilityKm: 25, thunder: false,
        },
        {
          at: '2026-07-18T03:00:00Z', condition: 'rain', cloudCoverPercent: 90,
          windSpeedMps: 4, precipitationMm: 2.5, visibilityKm: 8, thunder: true,
        },
      ] } },
    }),
  });

  assert.equal(result.ok, true);
  assert.equal(result.body.coverage, 'full');
  assert.equal(result.body.samples[0].forecastAt, '2026-07-18T02:00:00.000Z');
  assert.equal(result.body.samples[1].forecastAt, '2026-07-18T03:00:00.000Z');
  assert.equal(result.body.samples[1].condition, 'rain');
  assert.equal(result.body.samples[1].stale, true);
  assert.equal(JSON.stringify(result.body).includes('latitude'), false);
  assert.equal(JSON.stringify(result.body).includes('longitude'), false);
});

test('route weather reports partial coverage and fails when no forecast matches', async () => {
  let call = 0;
  const partial = await routeWeatherForecast({
    body: request,
    now: () => now,
    fetchWeather: async () => {
      call += 1;
      return call === 1
        ? { ok: true, cache: 'miss', body: { forecast: { hourly: [{
            at: '2026-07-18T02:00:00Z', condition: 'cloudy', cloudCoverPercent: 50,
            windSpeedMps: 2, precipitationMm: 0, visibilityKm: 20, thunder: false,
          }] } } }
        : { ok: false, error: 'upstream_unavailable' };
    },
  });
  assert.equal(partial.ok, true);
  assert.equal(partial.body.coverage, 'partial');
  assert.equal(partial.body.availableSamples, 1);

  const unavailable = await routeWeatherForecast({
    body: request,
    now: () => now,
    fetchWeather: async () => ({ ok: false, error: 'upstream_unavailable' }),
  });
  assert.deepEqual(unavailable, { ok: false, error: 'upstream_unavailable' });
});
