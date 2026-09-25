import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

const { privateKey } = generateKeyPairSync('ed25519');

async function withServer(run) {
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'test-key',
    projectId: 'test-project',
    serviceToken: 'test-service-token',
    amapWebKey: 'test-amap-key',
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

// Provider counters, p95 latency and model disagreement are operational
// detail. They sit behind the same boundary as the business routes on purpose,
// so moving a route above the token check is a test failure rather than an
// exposure.
test('metrics stay behind the service token boundary', async () => {
  await withServer(async (baseUrl) => {
    assert.equal((await fetch(`${baseUrl}/metrics`)).status, 401);

    const wrongToken = await fetch(`${baseUrl}/metrics`, {
      headers: { Authorization: 'Bearer not-the-service-token' },
    });
    assert.equal(wrongToken.status, 401);

    const response = await fetch(`${baseUrl}/metrics`, {
      headers: { Authorization: 'Bearer test-service-token' },
    });
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /^text\/plain/);
    assert.equal(response.headers.get('cache-control'), 'no-store');
  });
});

test('liveness stays public but never carries operational detail', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/healthz`);

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });
});
