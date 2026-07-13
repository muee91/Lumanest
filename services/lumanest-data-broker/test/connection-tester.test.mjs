import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createConnectionTester,
  createLLMProfileTester,
} from '../src/admin/connection-tester.mjs';

function runtime() {
  return { snapshot: () => ({
    privateKey: {}, keyId: 'id', projectId: 'project', amapWebKey: 'amap',
    llmProfiles: [], settings: { aiEnabled: true, upstreamTimeoutMs: 2000 },
  }) };
}

test('reports real AMap success and separate LLM configuration state', async () => {
  const tester = createConnectionTester({ runtimeConfig: runtime(), fetcher: async () =>
    new Response(JSON.stringify({ status: '1' }), { status: 200 }) });
  assert.deepEqual(await tester(), { status: 'ok', services: { qweather: 'local_signing_ready', amap: 'ok', llm: 'unconfigured' } });
});

test('classifies authentication and malformed upstream responses', async () => {
  const authentication = createConnectionTester({ runtimeConfig: runtime(), fetcher: async () =>
    new Response('{}', { status: 401 }) });
  assert.equal((await authentication()).status, 'authentication_failed');

  const malformed = createConnectionTester({ runtimeConfig: runtime(), fetcher: async () =>
    new Response('not-json', { status: 200 }) });
  assert.equal((await malformed()).status, 'invalid_response');
});

test('tests one saved LLM profile and returns only a stable category', async () => {
  const profile = {
    id: 'deepseek-main', protocol: 'openai_compatible', providerId: 'deepseek',
    apiKey: 'profile-secret', baseUrl: 'https://api.deepseek.com', model: 'deepseek-chat',
    enabled: true, timeoutMs: 8_000, allowFallback: false,
  };
  const tester = createLLMProfileTester({
    runtimeConfig: { snapshot: () => ({ llmProfiles: [profile] }) },
    requester: async () => ({ ok: true, text: '{"status":"ok"}' }),
  });
  assert.deepEqual(await tester('deepseek-main'), { status: 'ok', profileId: 'deepseek-main' });
  assert.deepEqual(await tester('missing'), { status: 'profile_not_found', profileId: 'missing' });
});
