import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LLMPromptBudget,
  LLMRouteMetrics,
  routeNarrative,
} from '../src/llm/router.mjs';

const primary = {
  id: 'primary',
  protocol: 'openai_compatible',
  providerId: 'openai',
  apiKey: 'key',
  baseUrl: 'https://model.example/v1',
  model: 'model',
  enabled: true,
  allowFallback: false,
  timeoutMs: 8_000,
};

const routing = {
  primaryProfileId: 'primary',
  fallbackEnabled: false,
  fallbackProfileIds: [],
  maximumAttempts: 3,
};

function prompt(questionType, templateAnswer) {
  return {
    system: 'bounded assistant',
    user: JSON.stringify({
      questionType,
      templateAnswer,
      placeSummaries: [],
      tone: 'balanced',
    }),
  };
}

test('nearby, safety and current shooting prompts never contact a model', async () => {
  for (const questionType of ['nearby', 'safety', 'shootingPlan']) {
    let contacted = false;
    const result = await routeNarrative({
      profiles: [primary],
      routing,
      prompt: prompt(questionType, '只使用确定性答案。'),
      budget: new LLMPromptBudget(),
      metrics: new LLMRouteMetrics(),
      requester: async () => {
        contacted = true;
        return { ok: true, text: '{"answer":"不应调用"}' };
      },
    });
    assert.equal(contacted, false);
    assert.equal(result.ok, false);
    assert.equal(result.error, 'deterministic_only');
  }
});

test('prompt budget blocks repeated assistant rewrites before upstream', async () => {
  const budget = new LLMPromptBudget({ assistantLimit: 1 });
  let calls = 0;
  const input = {
    profiles: [primary],
    routing,
    prompt: prompt('why', '主要依据是低风速。'),
    budget,
    metrics: new LLMRouteMetrics(),
    requester: async () => {
      calls += 1;
      return { ok: true, text: '{"answer":"主要依据仍是低风速。"}' };
    },
  };

  const first = await routeNarrative(input);
  const second = await routeNarrative(input);

  assert.equal(first.ok, true);
  assert.equal(second.ok, false);
  assert.equal(second.error, 'rate_limited');
  assert.equal(calls, 1);
});

test('unsupported model facts are rejected instead of reaching the client', async () => {
  const metrics = new LLMRouteMetrics();
  const result = await routeNarrative({
    profiles: [primary],
    routing,
    prompt: prompt('timing', '当前窗口是18:20—18:45。'),
    budget: new LLMPromptBudget(),
    metrics,
    requester: async () => ({
      ok: true,
      text: '{"answer":"19:30出发成功率80%。"}',
    }),
  });

  assert.equal(result.ok, false);
  assert.equal(result.error, 'invalid_response');
  assert.equal(metrics.snapshot().guard_unsupported_number, 1);
});

test('fallback profiles require explicit allowFallback authorization', async () => {
  const calls = [];
  const blocked = {
    ...primary,
    id: 'blocked',
    allowFallback: false,
  };
  const allowed = {
    ...primary,
    id: 'allowed',
    allowFallback: true,
  };
  const result = await routeNarrative({
    profiles: [primary, blocked, allowed],
    routing: {
      ...routing,
      fallbackEnabled: true,
      fallbackProfileIds: ['blocked', 'allowed'],
    },
    prompt: prompt('why', '主要依据是低风速。'),
    budget: new LLMPromptBudget(),
    metrics: new LLMRouteMetrics(),
    requester: async ({ profile }) => {
      calls.push(profile.id);
      return profile.id === 'allowed'
        ? { ok: true, text: '{"answer":"主要依据仍是低风速。"}' }
        : { ok: false, error: 'timeout' };
    },
  });

  assert.deepEqual(calls, ['primary', 'allowed']);
  assert.equal(result.ok, true);
  assert.equal(result.profileId, 'allowed');
});
