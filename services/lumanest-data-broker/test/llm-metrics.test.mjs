import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { LLMRouteMetrics, routeNarrative } from '../src/llm/router.mjs';
import { guardRejectionReasons } from '../src/llm/grounding-guard.mjs';

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
const prompt = (questionType, templateAnswer) => ({
  system: 'bounded assistant',
  user: JSON.stringify({ questionType, templateAnswer, placeSummaries: [], tone: 'balanced' }),
});

function valueOf(text, series) {
  const line = text.split('\n').find((entry) => entry.startsWith(series));
  return line == null ? null : Number(line.split(' ')[1]);
}

test('every reason the guard returns is declared in the exported enum', async () => {
  const source = await readFile(new URL('../src/llm/grounding-guard.mjs', import.meta.url), 'utf8');
  const declared = new Set(
    [...source.matchAll(/reason: '([a-z_]+)'/g)].map((match) => match[1]),
  );

  assert.ok(declared.size > 0, 'source scan found no guard reasons; the pattern broke');
  for (const reason of declared) {
    assert.ok(guardRejectionReasons.includes(reason), `undeclared guard reason: ${reason}`);
  }
});

test('a rejected rewrite is attributed to its reason instead of invalid_response', async () => {
  const metrics = new LLMRouteMetrics();
  const canary = '成功率80%';

  const result = await routeNarrative({
    profiles: [primary],
    routing,
    prompt: prompt('timing', '当前窗口是18:20—18:45。'),
    metrics,
    requester: async () => ({ ok: true, text: `{"answer":"19:30出发${canary}。"}` }),
  });

  assert.equal(result.ok, false);
  assert.equal(result.error, 'invalid_response');

  const text = metrics.toPrometheus();
  const attributed = guardRejectionReasons
    .filter((reason) => valueOf(text, `lumanest_llm_guard_rejections_total{reason="${reason}"}`) === 1);

  assert.equal(attributed.length, 1, `expected exactly one attributed reason, saw ${JSON.stringify(attributed)}`);
  assert.equal(valueOf(text, 'lumanest_llm_guard_rejections_total{reason="other"}'), 0,
    'the reason must not fall into the catch-all bucket');
});

test('metric text never carries model or prompt content', async () => {
  const metrics = new LLMRouteMetrics();
  await routeNarrative({
    profiles: [primary],
    routing,
    prompt: prompt('timing', '当前窗口是18:20—18:45。'),
    metrics,
    requester: async () => ({ ok: true, text: '{"answer":"19:30出发成功率80%。"}' }),
  });

  const text = metrics.toPrometheus();
  for (const leak of ['19:30', '成功率', '当前窗口', 'bounded assistant', 'answer']) {
    assert.ok(!text.includes(leak), `metric output leaked ${leak}`);
  }
});

test('all label values are declared up front so absence is unambiguous', () => {
  const text = new LLMRouteMetrics().toPrometheus();

  for (const reason of guardRejectionReasons) {
    assert.equal(valueOf(text, `lumanest_llm_guard_rejections_total{reason="${reason}"}`), 0);
  }
  for (const event of [
    'requests', 'failed', 'primary_success', 'fallback_success', 'fallback_profile_blocked',
    'call_budget_exhausted', 'unconfigured', 'extraction_parse_failed', 'other',
  ]) {
    assert.equal(valueOf(text, `lumanest_llm_route_events_total{event="${event}"}`), 0);
  }
});

test('unexpected names cannot inject labels or grow cardinality', () => {
  const metrics = new LLMRouteMetrics();
  metrics.record('guard_uninvented_reason');
  metrics.record('guard_"; drop metric\nx');
  metrics.record('something_entirely_new');
  metrics.record('upstream_unavailable');

  const text = metrics.toPrometheus();

  assert.equal(valueOf(text, 'lumanest_llm_guard_rejections_total{reason="other"}'), 2);
  assert.equal(valueOf(text, 'lumanest_llm_route_events_total{event="other"}'), 1);
  assert.equal(valueOf(text, 'lumanest_llm_upstream_errors_total{error="unavailable"}'), 1);
  // No injected newline may forge an extra line: every emitted line is checked
  // against the exact shape we allow.
  assert.ok(!text.includes('drop metric'));
  for (const line of text.split('\n').filter((line) => line.length > 0 && !line.startsWith('#'))) {
    assert.match(line, /^lumanest_llm_[a-z_]+(\{(event|reason|error)="[a-z0-9_]+"\})? \d+$/);
  }
});
