import assert from 'node:assert/strict';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

async function withServer(run, { fetcher } = {}) {
  const server = createTokenBrokerServer({
    privateKey: {},
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
    fetcher,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('health check never requires a service token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/healthz`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });
});

test('wildlife endpoint returns regional aggregates without observation coordinates', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/wildlife/nearby?location=121.47,31.23&radiusKm=20`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.source, 'GBIF');
    assert.equal(body.scope, 'regional_wildlife_observations');
    assert.deepEqual(body.taxa, [
      {
        scientificName: 'Passer montanus',
        commonName: null,
        animalClass: 'bird',
        records: 2,
      },
      {
        scientificName: 'Lutra lutra',
        commonName: 'Eurasian Otter',
        animalClass: 'mammal',
        records: 1,
      },
    ]);
    assert.equal(JSON.stringify(body).includes('decimalLatitude'), false);
    assert.equal(JSON.stringify(body).includes('decimalLongitude'), false);
  }, {
    fetcher: async (url) => {
      const classKey = url.searchParams.get('classKey');
      const records = classKey === '212'
        ? [
          { species: 'Passer montanus', class: 'Aves', decimalLatitude: 31.2, decimalLongitude: 121.4 },
          { species: 'Passer montanus', class: 'Aves', decimalLatitude: 31.3, decimalLongitude: 121.5 },
        ]
        : classKey === '359'
        ? [
          { species: 'Lutra lutra', vernacularName: 'Eurasian Otter', class: 'Mammalia', decimalLatitude: 31.2, decimalLongitude: 121.4 },
          { species: 'Felis catus', class: 'Mammalia', decimalLatitude: 31.2, decimalLongitude: 121.4 },
        ]
        : [];
      return new Response(JSON.stringify({ results: records }), { status: 200 });
    },
  });
});

test('Amap proxy requires the app service token', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/nearby?location=121.47,31.23`);
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'unauthorized' });
  });
});

test('Amap proxy rejects malformed coordinates before forwarding', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/amap/nearby?location=not-a-coordinate`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: 'invalid_location' });
  });
});
