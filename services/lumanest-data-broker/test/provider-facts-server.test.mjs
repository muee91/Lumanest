import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

async function withServer(providerFactsService, run) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
    providerFactsService,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('provider facts endpoint authenticates, validates and forwards a bounded query', async () => {
  const calls = [];
  const service = {
    facts: async (query) => {
      calls.push(query);
      return {
        contractVersion: 1,
        requestedCoordinate: { latitude: query.latitude, longitude: query.longitude, system: 'wgs84' },
        radiusKm: query.radiusKm,
        generatedAt: '2026-08-03T08:00:00.000Z',
        expiresAt: '2026-08-03T08:30:00.000Z',
        status: 'partial',
        cacheStatus: 'miss',
        providers: [],
      };
    },
  };

  await withServer(service, async (baseUrl) => {
    const unauthorized = await fetch(`${baseUrl}/v1/environment/provider-facts?lat=30&lon=120`);
    assert.equal(unauthorized.status, 401);

    const invalid = await fetch(`${baseUrl}/v1/environment/provider-facts?lat=30&lon=120&include=unknown`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(invalid.status, 400);

    const response = await fetch(
      `${baseUrl}/v1/environment/provider-facts?lat=30.25&lon=120.15&radiusKm=20&include=osm,wikidata&locale=zh-CN`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).contractVersion, 1);
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].latitude, 30.25);
  assert.equal(calls[0].longitude, 120.15);
  assert.equal(calls[0].radiusKm, 20);
  assert.deepEqual(calls[0].providerIds, ['osm', 'wikidata']);
});
