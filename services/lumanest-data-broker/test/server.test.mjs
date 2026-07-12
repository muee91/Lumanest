import assert from 'node:assert/strict';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

async function withServer(run) {
  const server = createTokenBrokerServer({
    privateKey: {},
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
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
