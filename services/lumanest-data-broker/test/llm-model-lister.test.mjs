import assert from 'node:assert/strict';
import test from 'node:test';

import { listModels } from '../src/llm/model-lister.mjs';

const profile = {
  id: 'openai-main', name: 'OpenAI 主模型', providerId: 'openai',
  protocol: 'openai_compatible', apiKey: 'model-secret',
  baseUrl: 'https://api.example/v1', model: 'gpt-4.1',
  enabled: true, timeoutMs: 8_000, allowFallback: false,
};

test('lists bounded deduplicated models from an OpenAI-compatible endpoint', async () => {
  const calls = [];
  const result = await listModels({
    profile,
    fetcher: async (url, options) => {
      calls.push({ url: url.toString(), options });
      return new Response(JSON.stringify({
        data: [{ id: 'gpt-4.1' }, { id: 'gpt-4.1' }, { id: 'gpt-4o' }, { id: '' }],
      }), { status: 200 });
    },
  });
  assert.deepEqual(result, { ok: true, models: ['gpt-4.1', 'gpt-4o'] });
  assert.equal(calls[0].url, 'https://api.example/v1/models');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer model-secret');
});

test('uses the native Gemini model catalog and normalizes names', async () => {
  const result = await listModels({
    profile: { ...profile, providerId: 'gemini', protocol: 'google_generate_content', baseUrl: 'https://generativelanguage.googleapis.com/v1beta', model: 'gemini-2.5-pro' },
    fetcher: async (url) => {
      assert.equal(url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models?key=model-secret');
      return new Response(JSON.stringify({ models: [{ name: 'models/gemini-2.5-pro' }] }), { status: 200 });
    },
  });
  assert.deepEqual(result, { ok: true, models: ['gemini-2.5-pro'] });
});

test('returns a stable error without exposing upstream response bodies', async () => {
  const result = await listModels({ profile, fetcher: async () => new Response('private upstream detail', { status: 401 }) });
  assert.deepEqual(result, { ok: false, error: 'authentication_failed' });
});
