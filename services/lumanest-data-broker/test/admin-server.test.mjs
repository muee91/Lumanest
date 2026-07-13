import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { createAdminServer } from '../src/admin/admin-server.mjs';
import { AdminAuthService } from '../src/admin/auth.mjs';
import { AuditLog } from '../src/admin/audit-log.mjs';
import { validateRuntimeSettings } from '../src/admin/runtime-settings.mjs';

async function withAdmin(run) {
  const directory = await mkdtemp(join(tmpdir(), 'lumanest-admin-server-'));
  const authService = new AdminAuthService({
    filePath: join(directory, 'auth.json'),
    bootstrapPassword: 'initial-password',
  });
  await authService.initialize();
  let snapshot = Object.freeze({
    revision: 1,
    privateKey: generateKeyPairSync('ed25519').privateKey,
    keyId: 'key-id-1234', projectId: 'project-5678',
    serviceToken: 'service-secret-9012', amapWebKey: 'amap-secret-3456',
    aiApiKey: 'ai-secret-7890', aiBaseUrl: 'https://example.test/v1', aiModel: 'qwen-plus',
    settings: validateRuntimeSettings({}),
  });
  const operations = [];
  const runtimeConfig = {
    snapshot: () => snapshot,
    replace: async (patch) => {
      snapshot = Object.freeze({ ...snapshot, ...patch, revision: snapshot.revision + 1 });
      return snapshot;
    },
  };
  const server = createAdminServer({
    authService, runtimeConfig, auditLog: new AuditLog(),
    testConnection: async () => ({ status: 'ok' }),
    clearCache: async () => operations.push('clear'),
    restart: async () => operations.push('restart'),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    await run({ baseUrl: `http://127.0.0.1:${server.address().port}`, operations });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
}

async function login(baseUrl) {
  const response = await fetch(`${baseUrl}/admin-api/login`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ password: 'initial-password' }),
  });
  const value = await response.json();
  return { cookie: response.headers.get('set-cookie').split(';')[0], csrf: value.csrfToken };
}

test('LAN login and authenticated config never reveal raw secrets', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const unauthenticated = await fetch(`${baseUrl}/admin-api/config`);
    assert.equal(unauthenticated.status, 401);
    assert.equal(unauthenticated.headers.get('cache-control'), 'no-store');

    const credentials = await login(baseUrl);
    const response = await fetch(`${baseUrl}/admin-api/config`, {
      headers: { Cookie: credentials.cookie, 'X-Forwarded-For': '8.8.8.8' },
    });
    assert.equal(response.status, 200);
    const text = await response.text();
    assert.equal(text.includes('service-secret-9012'), false);
    assert.equal(text.includes('ai-secret-7890'), false);
    assert.equal(JSON.parse(text).services.serviceToken.lastFour, '9012');
  });
});

test('mutations require CSRF and supported operations remain authenticated', async () => {
  await withAdmin(async ({ baseUrl, operations }) => {
    const credentials = await login(baseUrl);
    const withoutCsrf = await fetch(`${baseUrl}/admin-api/clear-cache`, {
      method: 'POST', headers: { Cookie: credentials.cookie },
    });
    assert.equal(withoutCsrf.status, 403);

    const headers = { Cookie: credentials.cookie, 'X-CSRF-Token': credentials.csrf, 'Content-Type': 'application/json' };
    assert.equal((await fetch(`${baseUrl}/admin-api/test-connection`, { method: 'POST', headers, body: '{}' })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin-api/config`, { method: 'PUT', headers, body: JSON.stringify({ aiModel: 'next-model' }) })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin-api/clear-cache`, { method: 'POST', headers, body: '{}' })).status, 200);
    assert.equal((await fetch(`${baseUrl}/admin-api/audit`, { headers: { Cookie: credentials.cookie } })).status, 200);
    assert.deepEqual(operations, ['clear']);
  });
});

test('rejects request bodies larger than 16 KiB before processing', async () => {
  await withAdmin(async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/admin-api/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password: 'x'.repeat(17 * 1024) }),
    });
    assert.equal(response.status, 413);
  });
});
