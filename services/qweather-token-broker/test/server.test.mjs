import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import test from 'node:test';

import { createTokenBrokerServer } from '../src/server.mjs';

async function startServer() {
  const { privateKey } = generateKeyPairSync('ed25519');
  const server = createTokenBrokerServer({
    privateKey,
    keyId: 'credential-id',
    projectId: 'project-id',
    serviceToken: 'local-test-service-token',
    now: () => new Date('2026-07-12T00:00:00Z'),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

test('health endpoint is public and does not reveal configuration', async (t) => {
  const service = await startServer();
  t.after(service.close);

  const response = await fetch(`${service.baseUrl}/healthz`);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
});

test('token endpoint rejects unauthenticated callers', async (t) => {
  const service = await startServer();
  t.after(service.close);

  const response = await fetch(`${service.baseUrl}/v1/qweather/token`, {
    method: 'POST',
  });

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: 'unauthorized' });
});

test('token endpoint returns a short-lived JWT to an authenticated caller', async (t) => {
  const service = await startServer();
  t.after(service.close);

  const response = await fetch(`${service.baseUrl}/v1/qweather/token`, {
    method: 'POST',
    headers: { Authorization: 'Bearer local-test-service-token' },
  });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.match(body.token, /^[^.]+\.[^.]+\.[^.]+$/);
  assert.equal(body.expiresAt, '2026-07-12T00:14:30.000Z');
  assert.deepEqual(Object.keys(body).sort(), ['expiresAt', 'token']);
});
