import assert from 'node:assert/strict';
import test from 'node:test';

import {
  SiteEnvironmentService,
  relativeRadianceBand,
  validSiteEnvironmentQuery,
} from '../src/environment/site-environment-service.mjs';

const directions = [
  ['north', 0],
  ['northeast', 45],
  ['east', 90],
  ['southeast', 135],
  ['south', 180],
  ['southwest', 225],
  ['west', 270],
  ['northwest', 315],
];

function spatialAnalysis({ dominantDirection = 'southeast', dominantAzimuthDegrees = 135 } = {}) {
  return {
    analysisVersion: 'viirs-spatial-radiance.1',
    maximumRadiusKm: 20,
    neighborhoods: [
      { radiusKm: 1, sampleCount: 12, coverageRatio: 1, median: 0.1, p90: 0.2, maximum: 0.3 },
      { radiusKm: 5, sampleCount: 80, coverageRatio: 0.95, median: 0.2, p90: 0.4, maximum: 1.2 },
      { radiusKm: 20, sampleCount: 1200, coverageRatio: 0.9, median: 0.3, p90: 1.5, maximum: 12 },
    ],
    lightDomes: {
      innerRadiusKm: 1,
      outerRadiusKm: 20,
      sectorCount: 8,
      dominantDirection,
      dominantAzimuthDegrees,
      sectors: directions.map(([direction, azimuthCenterDegrees]) => ({
        direction,
        azimuthCenterDegrees,
        sampleCount: 100,
        coverageRatio: 0.9,
        median: direction === 'southeast' ? 1.2 : 0.2,
        p90: direction === 'southeast' ? 8 : 0.4,
        maximum: direction === 'southeast' ? 12 : 0.8,
        peakDistanceKm: direction === 'southeast' ? 14 : 8,
      })),
    },
  };
}

function rasterPayload(overrides = {}) {
  return {
    status: 'ready',
    radiance: 0.42,
    datasetYear: 2024,
    datasetRevision: 'eog-v2.2-2024-median-masked-r1',
    resolutionMeters: 500,
    sampledLatitude: 28.451,
    sampledLongitude: 98.879,
    spatialAnalysis: spatialAnalysis(),
    sourceId: 'eog-viirs-annual-v2.2',
    attribution: 'Earth Observation Group VIIRS annual nighttime lights',
    ...overrides,
  };
}

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

test('service combines terrain with validated spatial VIIRS facts', async () => {
  const calls = [];
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    rasterServiceToken: 'internal-secret',
    rasterDatasetRevision: 'eog-v2.2-2024-median-masked-r1',
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async (url, options = {}) => {
      calls.push({ url: url.toString(), options });
      if (url.hostname === 'api.open-meteo.com') {
        assert.equal(url.searchParams.get('latitude'), '28.45');
        assert.equal(url.searchParams.get('longitude'), '98.88');
        return new Response(JSON.stringify({ elevation: [3260] }));
      }
      assert.equal(url.pathname, '/v1/viirs/sample');
      assert.equal(options.headers.Authorization, 'Bearer internal-secret');
      return new Response(JSON.stringify(rasterPayload()));
    },
  });

  const body = await service.facts({ latitude: 28.4502, longitude: 98.8802 });
  assert.equal(body.contractVersion, 3);
  assert.deepEqual(body.requestedCoordinate, {
    latitude: 28.4502,
    longitude: 98.8802,
    system: 'wgs84',
  });
  assert.equal(body.terrain.status, 'ready');
  assert.equal(body.terrain.elevationMeters, 3260);
  assert.equal(body.terrain.cacheStatus, 'miss');
  assert.equal(body.terrain.source.revision, 'copernicus-dem-glo90-2021');
  assert.equal(body.nightSkyBackground.status, 'ready');
  assert.equal(body.nightSkyBackground.radiance, 0.42);
  assert.equal(body.nightSkyBackground.relativeRadianceBand, 'dark');
  assert.equal(body.nightSkyBackground.datasetRevision, 'eog-v2.2-2024-median-masked-r1');
  assert.equal(
    body.nightSkyBackground.spatialAnalysis.neighborhoods[2].relativeRadianceBand,
    'moderate',
  );
  assert.equal(
    body.nightSkyBackground.spatialAnalysis.lightDomes.dominantDirection,
    'southeast',
  );
  assert.equal(
    body.nightSkyBackground.spatialAnalysis.lightDomes.sectors[3].relativeRadianceBand,
    'bright',
  );
  assert.deepEqual(body.nightSkyBackground.sampledCoordinate, {
    latitude: 28.451,
    longitude: 98.879,
    system: 'wgs84',
  });
  assert.equal(calls.length, 2);
});

test('service rejects inconsistent spatial light-dome analysis', async () => {
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    rasterServiceToken: 'internal-secret',
    rasterDatasetRevision: 'eog-v2.2-2024-median-masked-r1',
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async (url) => url.hostname === 'api.open-meteo.com'
      ? new Response(JSON.stringify({ elevation: [56] }))
      : new Response(JSON.stringify(rasterPayload({
          spatialAnalysis: spatialAnalysis({
            dominantDirection: 'west',
            dominantAzimuthDegrees: 270,
          }),
        }))),
  });

  const body = await service.facts({ latitude: 30.25, longitude: 120.15 });
  assert.equal(body.terrain.status, 'ready');
  assert.equal(body.nightSkyBackground.status, 'unavailable');
  assert.equal(body.nightSkyBackground.spatialAnalysis, null);
});

test('service requires an internal token before calling the raster service', async () => {
  const calls = [];
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async (url) => {
      calls.push(url.toString());
      return new Response(JSON.stringify({ elevation: [56] }));
    },
  });

  const body = await service.facts({ latitude: 30.25, longitude: 120.15 });
  assert.equal(body.terrain.status, 'ready');
  assert.equal(body.nightSkyBackground.status, 'unconfigured');
  assert.equal(calls.length, 1);
  assert.match(calls[0], /api\.open-meteo\.com/);
});

test('coarse-cell cache keeps requested and sampled coordinates distinct', async () => {
  let calls = 0;
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    rasterServiceToken: 'internal-secret',
    rasterDatasetRevision: 'eog-v2.2-2024-median-masked-r1',
    now: () => new Date('2026-07-22T12:00:00Z'),
    fetcher: async (url) => {
      calls += 1;
      return url.hostname === 'api.open-meteo.com'
        ? new Response(JSON.stringify({ elevation: [88] }))
        : new Response(JSON.stringify(rasterPayload({
            radiance: 1.1,
            sampledLatitude: 30.2505,
            sampledLongitude: 120.1505,
          })));
    },
  });

  const first = await service.facts({ latitude: 30.2501, longitude: 120.1501 });
  const second = await service.facts({ latitude: 30.2502, longitude: 120.1502 });
  assert.equal(first.terrain.cacheStatus, 'miss');
  assert.equal(second.terrain.cacheStatus, 'hit');
  assert.equal(second.nightSkyBackground.cacheStatus, 'hit');
  assert.notDeepEqual(first.requestedCoordinate, second.requestedCoordinate);
  assert.deepEqual(first.terrain.sampledCoordinate, second.terrain.sampledCoordinate);
  assert.deepEqual(
    first.nightSkyBackground.sampledCoordinate,
    second.nightSkyBackground.sampledCoordinate,
  );
  assert.equal(calls, 2);
});

test('terrain remains cached when the independently degraded night-sky fact expires', async () => {
  let instant = new Date('2026-07-22T12:00:00Z');
  let elevationCalls = 0;
  const service = new SiteEnvironmentService({
    rasterServiceUrl: 'http://raster.internal:8792',
    now: () => instant,
    fetcher: async () => {
      elevationCalls += 1;
      return new Response(JSON.stringify({ elevation: [126] }));
    },
  });

  const first = await service.facts({ latitude: 30.25, longitude: 120.15 });
  instant = new Date('2026-07-22T12:10:00Z');
  const second = await service.facts({ latitude: 30.25, longitude: 120.15 });
  assert.equal(first.terrain.cacheStatus, 'miss');
  assert.equal(first.nightSkyBackground.cacheStatus, 'miss');
  assert.equal(second.terrain.cacheStatus, 'hit');
  assert.equal(second.nightSkyBackground.cacheStatus, 'miss');
  assert.equal(elevationCalls, 1);
});
