import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

async function withServer(skyWindowService, run) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
    siteEnvironmentService: { facts: async () => ({}) },
    skyWindowService,
    now: () => new Date('2026-07-23T15:00:00Z'),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('sky-window endpoint authenticates, validates, and forwards bounded query', async () => {
  const calls = [];
  await withServer({
    forecast: async (query) => {
      calls.push(query);
      return { contractVersion: 1, algorithmVersion: 'sky-window-forecast.1' };
    },
  }, async (baseUrl) => {
    const path = '/v1/environment/sky-windows?lat=30&lon=100&start=' +
      encodeURIComponent('2026-07-23T15:00:00.000Z') + '&hours=24&locale=zh-CN';
    const unauthorized = await fetch(`${baseUrl}${path}`);
    assert.equal(unauthorized.status, 401);

    const invalid = await fetch(
      `${baseUrl}/v1/environment/sky-windows?lat=30&lon=100&start=bad&hours=24`,
      { headers: { Authorization: 'Bearer test-service-token' } },
    );
    assert.equal(invalid.status, 400);

    const response = await fetch(`${baseUrl}${path}`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).contractVersion, 1);
  });
  assert.deepEqual(calls, [{
    latitude: 30,
    longitude: 100,
    startAt: '2026-07-23T15:00:00.000Z',
    hours: 24,
    locale: 'zh-CN',
  }]);
});
