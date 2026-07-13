import assert from 'node:assert/strict';
import test from 'node:test';

import { createConnectionTester } from '../src/admin/connection-tester.mjs';

function runtime(aiApiKey = '') {
  return { snapshot: () => ({
    privateKey: {}, keyId: 'id', projectId: 'project', amapWebKey: 'amap',
    aiApiKey, aiBaseUrl: 'https://ai.example/v1', settings: { aiEnabled: true, upstreamTimeoutMs: 2000 },
  }) };
}

test('reports real AMap success and skips unconfigured AI', async () => {
  const tester = createConnectionTester({ runtimeConfig: runtime(), fetcher: async () =>
    new Response(JSON.stringify({ status: '1' }), { status: 200 }) });
  assert.deepEqual(await tester(), { status: 'ok', services: { qweather: 'local_signing_ready', amap: 'ok', ai: 'unconfigured' } });
});

test('classifies authentication and malformed upstream responses', async () => {
  const authentication = createConnectionTester({ runtimeConfig: runtime(), fetcher: async () =>
    new Response('{}', { status: 401 }) });
  assert.equal((await authentication()).status, 'authentication_failed');

  const malformed = createConnectionTester({ runtimeConfig: runtime(), fetcher: async () =>
    new Response('not-json', { status: 200 }) });
  assert.equal((await malformed()).status, 'invalid_response');
});

test('checks configured AI without exposing credentials', async () => {
  const urls = [];
  const tester = createConnectionTester({ runtimeConfig: runtime('secret-key'), fetcher: async (url) => {
    urls.push(url.toString());
    return urls.length === 1
      ? new Response(JSON.stringify({ status: '1' }), { status: 200 })
      : new Response(JSON.stringify({ data: [] }), { status: 200 });
  } });
  const result = await tester();
  assert.equal(result.services.ai, 'ok');
  assert.equal(JSON.stringify(result).includes('secret-key'), false);
});
