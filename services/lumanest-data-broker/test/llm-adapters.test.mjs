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
  assert.equal(captured.url.searchParams.has('key'), false);
  assert.equal(captured.options.headers['x-goog-api-key'], 'secret-key');
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

test('adapter combines caller cancellation with the provider timeout', async () => {
  const controller = new AbortController();
  controller.abort();
  let observedSignal;
  const result = await requestNarrative({
    profile: profile('openai_compatible'),
    prompt,
    signal: controller.signal,
    fetcher: async (_url, options) => {
      observedSignal = options.signal;
      throw new DOMException('cancelled', 'AbortError');
    },
  });

  assert.equal(observedSignal.aborted, true);
  assert.deepEqual(result, { ok: false, error: 'timeout' });
});

test('openai_compatible with tools drops response_format and parses tool_calls', async () => {
  let captured;
  const result = await requestNarrative({
    profile: profile('openai_compatible'),
    prompt,
    tools: [{
      type: 'function',
      function: { name: 'web_search', description: 'search the web', parameters: { type: 'object', properties: { query: { type: 'string' } } } },
    }],
    fetcher: async (url, options) => {
      captured = { url, options };
      return new Response(JSON.stringify({
        choices: [{
          message: {
            content: null,
            tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'web_search', arguments: '{"query":"灵隐寺开放时间"}' } }],
          },
        }],
      }), { status: 200 });
    },
  });
  const body = JSON.parse(captured.options.body);
  // JSON mode must be dropped when tools are in play (OpenAI rejects the combo
  // and it would suppress tool_calls).
  assert.equal(body.response_format, undefined);
  assert.deepEqual(body.tool_choice, 'auto');
  assert.equal(Array.isArray(body.tools), true);
  // The agent loop receives a protocol-agnostic tool call with parsed args.
  assert.equal(result.ok, true);
  assert.equal(result.text, '');
  assert.deepEqual(result.toolCalls, [{ id: 'call_1', name: 'web_search', arguments: { query: '灵隐寺开放时间' } }]);
});

test('openai_compatible with tools surfaces a plain text answer with null toolCalls', async () => {
  const result = await requestNarrative({
    profile: profile('openai_compatible'),
    prompt,
    tools: [{ type: 'function', function: { name: 'web_search', parameters: { type: 'object' } } }],
    fetcher: async () => new Response(JSON.stringify({
      choices: [{ message: { content: '{"answer":"无需搜索"}' } }],
    }), { status: 200 }),
  });
  assert.equal(result.ok, true);
  assert.equal(result.text, '{"answer":"无需搜索"}');
  assert.equal(result.toolCalls, null);
});

test('anthropic and gemini degrade gracefully when tools are requested but unsupported', async () => {
  // These protocols do not yet expose withTools/extractToolCalls, so passing
  // tools must fall back to a plain chat completion rather than failing.
  for (const protocol of ['anthropic_messages', 'google_generate_content']) {
    const result = await requestNarrative({
      profile: profile(protocol),
      prompt,
      tools: [{ type: 'function', function: { name: 'web_search', parameters: { type: 'object' } } }],
      fetcher: async () => new Response(JSON.stringify(
        protocol === 'anthropic_messages'
          ? { content: [{ type: 'text', text: '{"answer":"ok"}' }] }
          : { candidates: [{ content: { parts: [{ text: '{"answer":"ok"}' }] } }] },
      ), { status: 200 }),
    });
    assert.equal(result.ok, true);
    assert.equal(result.toolCalls, undefined);
  }
});
