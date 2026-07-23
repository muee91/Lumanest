import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

async function withServer(siteEnvironmentService, run, options = {}) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
    siteEnvironmentService,
    ...options,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('default site environment service forwards private raster and terrain configuration', async () => {
  const calls = [];
  await withServer(null, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/environment/site-facts?lat=30.25&lon=120.15&include=skyAssessment&at=2026-07-23T15%3A00%3A00.000Z`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).contractVersion, 4);
  }, {
    rasterServiceUrl: 'http://raster.internal:8792',
    rasterServiceToken: 'raster-secret',
    rasterDatasetRevision: 'eog-v2.2-2024-median-masked-r1',
    terrainServiceUrl: 'http://terrain.internal:8793',
    terrainServiceToken: 'terrain-secret',
    terrainHorizonDatasetRevision: 'copernicus-glo30-2024-r1',
    fetcher: async (url, options = {}) => {
      calls.push({ url: url.toString(), authorization: options.headers?.Authorization ?? null });
      if (url.hostname === 'api.open-meteo.com') {
        return new Response(JSON.stringify({ elevation: [56] }));
      }
      return new Response(JSON.stringify({}), { status: 503 });
    },
  });
  assert.deepEqual(calls, [
    { url: 'https://api.open-meteo.com/v1/elevation?latitude=30.25&longitude=120.15', authorization: null },
    { url: 'http://raster.internal:8792/v1/viirs/sample?latitude=30.25&longitude=120.15', authorization: 'Bearer raster-secret' },
    { url: 'http://terrain.internal:8793/v1/dem/horizon?latitude=30.25&longitude=120.15', authorization: 'Bearer terrain-secret' },
  ]);
});

test('site environment endpoint is authenticated and validates coordinates', async () => {
  const calls = [];
  const service = {
    facts: async (query) => {
      calls.push(query);
      return {
        contractVersion: 1,
        coordinate: { ...query, system: 'wgs84' },
        terrain: { status: 'unavailable', elevationMeters: null, source: null },
        nightSkyBackground: {
          status: 'unconfigured', radiance: null, radianceUnit: 'nW/cm2/sr',
          relativeRadianceBand: null, classificationVersion: 'viirs-relative-radiance.1',
          datasetYear: null, resolutionMeters: null, source: null,
        },
        generatedAt: '2026-07-22T12:00:00.000Z',
        expiresAt: '2026-07-22T12:15:00.000Z',
        cacheStatus: 'miss',
      };
    },
  };

  await withServer(service, async (baseUrl) => {
    const unauthorized = await fetch(`${baseUrl}/v1/environment/site-facts?lat=30&lon=120`);
    assert.equal(unauthorized.status, 401);

    const invalid = await fetch(`${baseUrl}/v1/environment/site-facts?lat=91&lon=120`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(invalid.status, 400);

    const response = await fetch(`${baseUrl}/v1/environment/site-facts?lat=30.25&lon=120.15`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).contractVersion, 1);
  });
  assert.deepEqual(calls, [{ latitude: 30.25, longitude: 120.15 }]);
});
