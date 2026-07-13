import assert from 'node:assert/strict';
import test from 'node:test';

import { requestNarrative } from '../src/llm/adapters/index.mjs';

const prompt = { system: 'system instruction', user: 'bounded context' };

function profile(protocol, overrides = {}) {
  return {
    protocol, apiKey: 'secret-key', baseUrl: 'https://provider.example/v1',
    model: 'model-id', timeoutMs: 8_000, providerId: 'custom', ...overrides,
  };
}

test('OpenAI-compatible adapter sends chat completions and extracts content', async () => {
  let captured;
  const result = await requestNarrative({
    profile: profile('openai_compatible'), prompt,
    fetcher: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify({ choices: [{ message: { content: '{"summary":"ok"}' } }] }), { status: 200 });
    },
  });
  assert.equal(captured.url.href, 'https://provider.example/v1/chat/completions');
  assert.equal(captured.options.headers.Authorization, 'Bearer secret-key');
  const body = JSON.parse(captured.options.body);
  assert.equal(body.model, 'model-id');
  assert.deepEqual(body.messages, [
    { role: 'system', content: prompt.system }, { role: 'user', content: prompt.user },
  ]);
  assert.deepEqual(result, { ok: true, text: '{"summary":"ok"}' });
});

test('OpenAI-compatible adapter omits authorization for keyless Ollama', async () => {
  let headers;
  await requestNarrative({
    profile: profile('openai_compatible', { providerId: 'ollama', apiKey: '' }), prompt,
    fetcher: async (_url, options) => {
      headers = options.headers;
      return new Response(JSON.stringify({ choices: [{ message: { content: '{}' } }] }), { status: 200 });
    },
  });
  assert.equal(Object.hasOwn(headers, 'Authorization'), false);
});

test('Anthropic adapter uses Messages API headers and extracts a text block', async () => {
  let captured;
  const result = await requestNarrative({
    profile: profile('anthropic_messages'), prompt,
    fetcher: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify({ content: [{ type: 'text', text: '{"summary":"claude"}' }] }), { status: 200 });
    },
  });
  assert.equal(captured.url.href, 'https://provider.example/v1/messages');
  assert.equal(captured.options.headers['x-api-key'], 'secret-key');
  assert.equal(captured.options.headers['anthropic-version'], '2023-06-01');
  const body = JSON.parse(captured.options.body);
  assert.equal(body.system, prompt.system);
  assert.deepEqual(result, { ok: true, text: '{"summary":"claude"}' });
});

test('Gemini adapter uses GenerateContent and extracts candidate text', async () => {
  let captured;
  const result = await requestNarrative({
    profile: profile('google_generate_content'), prompt,
    fetcher: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify({
        candidates: [{ content: { parts: [{ text: '{"summary":"gemini"}' }] } }],
      }), { status: 200 });
    },
  });
  assert.equal(captured.url.pathname, '/v1/models/model-id:generateContent');
  assert.equal(captured.url.searchParams.get('key'), 'secret-key');
  const body = JSON.parse(captured.options.body);
  assert.equal(body.systemInstruction.parts[0].text, prompt.system);
  assert.deepEqual(result, { ok: true, text: '{"summary":"gemini"}' });
});

test('adapters return stable failure categories without upstream bodies', async () => {
  const cases = [[401, 'authentication_failed'], [403, 'authentication_failed'], [404, 'model_not_found'], [429, 'rate_limited'], [400, 'request_rejected'], [503, 'upstream_unavailable']];
  for (const [status, category] of cases) {
    const result = await requestNarrative({
      profile: profile('openai_compatible'), prompt,
      fetcher: async () => new Response('sensitive upstream body', { status }),
    });
    assert.deepEqual(result, { ok: false, error: category });
    assert.equal(JSON.stringify(result).includes('sensitive'), false);
  }
});

test('adapters classify timeout and malformed success responses', async () => {
  const timeout = await requestNarrative({
    profile: profile('openai_compatible'), prompt,
    fetcher: async () => { throw new DOMException('timed out', 'TimeoutError'); },
  });
  assert.deepEqual(timeout, { ok: false, error: 'timeout' });
  const malformed = await requestNarrative({
    profile: profile('openai_compatible'), prompt,
    fetcher: async () => new Response('{}', { status: 200 }),
  });
  assert.deepEqual(malformed, { ok: false, error: 'invalid_response' });
});
