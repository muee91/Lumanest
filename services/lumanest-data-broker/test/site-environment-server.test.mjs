import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

async function withServer(siteEnvironmentService, run) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
    siteEnvironmentService,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

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
