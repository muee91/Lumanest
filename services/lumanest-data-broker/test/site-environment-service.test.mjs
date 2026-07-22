import assert from 'node:assert/strict';
import test from 'node:test';

import {
  SiteEnvironmentService,
  relativeRadianceBand,
  validSiteEnvironmentQuery,
} from '../src/environment/site-environment-service.mjs';

test('site environment query accepts only finite WGS84 coordinates', () => {
  assert.deepEqual(
    validSiteEnvironmentQuery(new URLSearchParams('lat=30.25&lon=120.15')),
    { latitude: 30.25, longitude: 120.15 },
  );
  assert.equal(validSiteEnvironmentQuery(new URLSearchParams('lat=91&lon=120')), null);
  assert.equal(validSiteEnvironmentQuery(new URLSearchParams('lat=30&lon=nan')), null);
});

test('relative radiance bands remain explicitly non-Bortle', () => {
  assert.equal(relativeRadianceBand(0.1), 'veryDark');
  assert.equal(relativeRadianceBand(0.4), 'dark');
  assert.equal(relativeRadianceBand(1.5), 'moderate');
  assert.equal(relativeRadianceBand(8), 'bright');
  assert.equal(relativeRadianceBand(30), 'veryBright');
  assert.equal(relativeRadianceBand(-1), null);
});

test('service combines Copernicus elevation and a reviewed VIIRS raster sample', async () => {
  const calls = [];
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async (url) => {
      calls.push(url.toString());
      if (url.hostname === 'api.open-meteo.com') {
        return new Response(JSON.stringify({ elevation: [3260] }));
      }
      assert.equal(url.pathname, '/v1/viirs/sample');
      return new Response(JSON.stringify({
        status: 'ready',
        radiance: 0.42,
        datasetYear: 2024,
        resolutionMeters: 500,
        sourceId: 'eog-viirs-annual-v2.2',
        attribution: 'Earth Observation Group VIIRS annual nighttime lights',
      }));
    },
  });

  const body = await service.facts({ latitude: 28.45, longitude: 98.88 });
  assert.equal(body.terrain.status, 'ready');
  assert.equal(body.terrain.elevationMeters, 3260);
  assert.equal(body.nightSkyBackground.status, 'ready');
  assert.equal(body.nightSkyBackground.radiance, 0.42);
  assert.equal(body.nightSkyBackground.relativeRadianceBand, 'dark');
  assert.equal(body.nightSkyBackground.classificationVersion, 'viirs-relative-radiance.1');
  assert.equal(body.cacheStatus, 'miss');
  assert.equal(calls.length, 2);
});

test('service degrades light pollution independently when raster data is unconfigured', async () => {
  const service = new SiteEnvironmentService({
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async () => new Response(JSON.stringify({ elevation: [56] })),
  });

  const body = await service.facts({ latitude: 30.25, longitude: 120.15 });
  assert.equal(body.terrain.status, 'ready');
  assert.equal(body.nightSkyBackground.status, 'unconfigured');
});

test('service coalesces and caches equal coarse-cell requests', async () => {
  let calls = 0;
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async (url) => {
      calls += 1;
      return url.hostname === 'api.open-meteo.com'
        ? new Response(JSON.stringify({ elevation: [88] }))
        : new Response(JSON.stringify({
          status: 'ready', radiance: 1.1, datasetYear: 2024,
          resolutionMeters: 500, sourceId: 'eog-viirs-annual-v2.2',
        }));
    },
  });

  const first = await service.facts({ latitude: 30.2501, longitude: 120.1501 });
  const second = await service.facts({ latitude: 30.2502, longitude: 120.1502 });
  assert.equal(first.cacheStatus, 'miss');
  assert.equal(second.cacheStatus, 'hit');
  assert.equal(calls, 2);
});
