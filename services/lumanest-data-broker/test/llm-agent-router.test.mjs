import assert from 'node:assert/strict';
import test from 'node:test';

import { LLMCallBudget, routeAssistantAgent } from '../src/llm/router.mjs';
import { assistantTools, executeWebSearch } from '../src/llm/tools.mjs';

const prompt = {
  system: 'bounded assistant',
  user: JSON.stringify({
    questionType: 'creative',
    templateAnswer: '先确认开放时间再前往。',
    placeSummaries: [],
    contextFacts: '',
    tone: 'balanced',
  }),
};

function profile(overrides = {}) {
  return {
    id: 'primary', protocol: 'openai_compatible', enabled: true,
    apiKey: 'k', baseUrl: 'https://p.example/v1', model: 'm',
    timeoutMs: 8_000, providerId: 'custom', ...overrides,
  };
}

const routing = { primaryProfileId: 'primary', fallbackEnabled: false, fallbackProfileIds: [], maximumAttempts: 1 };

function sseToolCall(name, args, id = 'call_1') {
  return JSON.stringify({
    choices: [{
      message: { content: null, tool_calls: [{ id, type: 'function', function: { name, arguments: JSON.stringify(args) } }] },
    }],
  });
}

function sseText(text) {
  return JSON.stringify({ choices: [{ message: { content: text } }] });
}

async function collect(gen) {
  const events = [];
  for await (const e of gen) events.push(e);
  return events;
}

test('agent runs one web_search round then grounds the final answer', async () => {
  const calls = [];
  const fetcher = async (url, options) => {
    const body = JSON.parse(options.body);
    const hasToolResult = (body.messages ?? []).some((m) => m.role === 'tool');
    calls.push({ hasToolResult, tools: body.tools });
    return new Response(
      hasToolResult ? sseText(JSON.stringify({ answer: '灵隐寺7:00开门，可前往。' })) : sseToolCall('web_search', { query: '灵隐寺开放时间' }),
      { status: 200 },
    );
  };
  const executeTool = async ({ query }) => {
    assert.equal(query, '灵隐寺开放时间');
    return {
      ok: true,
      excerpt: '灵隐寺开放时间（杭州日报）：每日7:00开门。',
      results: [{ title: '灵隐寺开放时间', snippet: '每日7:00开门', publisher: '杭州日报', url: 'https://hangzhou.example/x' }],
    };
  };
  const events = await collect(routeAssistantAgent({
    profiles: [profile()], routing, prompt, fetcher, tools: assistantTools, executeTool,
  }));
  const result = events.find((e) => e.type === 'result');
  assert.equal(result.ok, true);
  assert.equal(result.profileId, 'primary');
  assert.deepEqual(result.sources, [{
    title: '灵隐寺开放时间', publisher: '杭州日报', url: 'https://hangzhou.example/x',
  }]);
  // Two upstream calls: first returned a tool call, second produced the answer.
  assert.equal(calls.length, 2);
  assert.equal(calls[0].hasToolResult, false);
  assert.equal(calls[1].hasToolResult, true);
  // Both calls carry the tools array (tool_choice auto throughout).
  assert.ok(Array.isArray(calls[0].tools) && calls[0].tools.length > 0);
  assert.ok(Array.isArray(calls[1].tools) && calls[1].tools.length > 0);
});

test('agent degrades when the model returns text without a tool call', async () => {
  const fetcher = async () => new Response(sseText(JSON.stringify({ answer: '无需搜索，看窗口即可。' })), { status: 200 });
  const executeTool = async () => { throw new Error('should not be called'); };
  const events = await collect(routeAssistantAgent({
    profiles: [profile()], routing, prompt, fetcher, tools: assistantTools, executeTool,
  }));
  const result = events.find((e) => e.type === 'result');
  assert.equal(result.ok, true);
  assert.equal(JSON.parse(result.text).answer, '无需搜索，看窗口即可。');
});

test('agent stops after one tool round if the model calls tools again', async () => {
  const fetcher = async () => new Response(sseToolCall('web_search', { query: 'again' }, 'call_2'), { status: 200 });
  const executeTool = async () => ({ ok: true, excerpt: 'x', results: [] });
  const events = await collect(routeAssistantAgent({
    profiles: [profile()], routing, prompt, fetcher, tools: assistantTools, executeTool,
  }));
  const result = events.find((e) => e.type === 'result');
  assert.equal(result.ok, false);
  assert.equal(result.error, 'tool_loop_exceeded');
});

test('agent and final answer share one paid-call budget', async () => {
  let calls = 0;
  const callBudget = new LLMCallBudget({ limit: 1 });
  const events = await collect(routeAssistantAgent({
    profiles: [profile()],
    routing,
    prompt,
    callBudget,
    tools: assistantTools,
    fetcher: async () => {
      calls += 1;
      return new Response(sseToolCall('web_search', { query: '灵隐寺开放时间' }), { status: 200 });
    },
    executeTool: async () => ({ ok: true, excerpt: '灵隐寺闭园。', results: [] }),
  }));

  const result = events.find((event) => event.type === 'result');
  assert.equal(result.ok, false);
  assert.equal(result.error, 'rate_limited');
  assert.equal(calls, 1);
  assert.equal(callBudget.used, 1);
});

test('agent rejects an unknown tool name', async () => {
  const fetcher = async () => new Response(sseToolCall('other_tool', {}), { status: 200 });
  const events = await collect(routeAssistantAgent({
    profiles: [profile()], routing, prompt, fetcher, tools: assistantTools, executeTool: async () => ({ ok: true, excerpt: '', results: [] }),
  }));
  const result = events.find((e) => e.type === 'result');
  assert.equal(result.ok, false);
  assert.equal(result.error, 'unknown_tool');
});

test('agent falls back when the first upstream call fails', async () => {
  const fetcher = async () => new Response('{}', { status: 503 });
  const events = await collect(routeAssistantAgent({
    profiles: [profile()], routing, prompt, fetcher, tools: assistantTools, executeTool: async () => ({ ok: true, excerpt: '', results: [] }),
  }));
  const result = events.find((e) => e.type === 'result');
  assert.equal(result.ok, false);
  assert.equal(result.error, 'upstream_unavailable');
});

test('agent continues to a final answer when the tool returns no results', async () => {
  const fetcher = async (_url, options) => {
    const body = JSON.parse(options.body);
    const hasToolResult = (body.messages ?? []).some((m) => m.role === 'tool');
    return new Response(
      hasToolResult ? sseText(JSON.stringify({ answer: '先确认开放时间再前往。' })) : sseToolCall('web_search', { query: 'x' }),
      { status: 200 },
    );
  };
  const executeTool = async () => ({ ok: false, error: 'upstream_unavailable' });
  const events = await collect(routeAssistantAgent({
    profiles: [profile()], routing, prompt, fetcher, tools: assistantTools, executeTool,
  }));
  const result = events.find((e) => e.type === 'result');
  // The model still produced a grounded answer using the template/contextFacts,
  // so the loop is treated as success despite the empty search.
  assert.equal(result.ok, true);
});

test('executeWebSearch rejects an unconfigured profile', async () => {
  const result = await executeWebSearch({ query: 'x', profile: { enabled: false, sourcePolicies: [] }, fetcher: async () => null });
  assert.equal(result.ok, false);
  assert.equal(result.error, 'search_unconfigured');
});

test('executeWebSearch delegates to searchTavily with whitelisted domains', async () => {
  let captured;
  const fetcher = async (url, options) => {
    captured = { url, body: JSON.parse(options.body) };
    return new Response(JSON.stringify({
      results: [{ title: '灵隐寺开放时间', content: '每日7:00开门', url: 'https://hangzhou.example/x', published_date: '2026-07-01' }],
    }), { status: 200 });
  };
  const profile = {
    enabled: true,
    apiKey: 'tavily-key',
    baseUrl: 'https://api.tavily.com',
    timeoutMs: 8_000,
    sourcePolicies: [{ id: 'hz', domain: 'hangzhou.example', attribution: '杭州日报', license: 'open', version: '1', enabled: true }],
  };
  const result = await executeWebSearch({ query: '灵隐寺开放时间', profile, fetcher });
  assert.equal(result.ok, true);
  assert.match(result.excerpt, /灵隐寺开放时间/);
  assert.match(result.excerpt, /杭州日报/);
  // The search request restricts include_domains to the whitelisted policy.
  assert.deepEqual(captured.body.include_domains, ['hangzhou.example']);
  assert.equal(captured.body.api_key, 'tavily-key');
});
