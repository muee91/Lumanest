import assert from 'node:assert/strict';
import test from 'node:test';

import { routeNarrative } from '../src/llm/router.mjs';

const prompt = { system: 'system', user: 'user' };
const primary = {
  id: 'primary', protocol: 'openai_compatible', providerId: 'openai',
  apiKey: 'one', baseUrl: 'https://primary.example/v1', model: 'model',
  enabled: true, allowFallback: false, timeoutMs: 8_000,
};
const fallback = (id) => ({
  ...primary, id, apiKey: id, baseUrl: `https://${id}.example/v1`, allowFallback: true,
});
const routing = {
  primaryProfileId: 'primary', fallbackEnabled: false,
  fallbackProfileIds: [], maximumAttempts: 3,
};

test('returns unconfigured without an explicitly selected primary profile', async () => {
  const result = await routeNarrative({ profiles: [], routing: { ...routing, primaryProfileId: null }, prompt });
  assert.deepEqual(result, { ok: false, error: 'ai_unconfigured', attempts: [] });
});

test('does not send a narrative request for an unselected draft model', async () => {
  const result = await routeNarrative({
    profiles: [{ ...primary, model: '' }], routing, prompt,
    requester: async () => { throw new Error('must not be called'); },
  });
  assert.deepEqual(result, { ok: false, error: 'ai_unconfigured', attempts: [] });
});

test('primary success stops without contacting fallback profiles', async () => {
  const calls = [];
  const result = await routeNarrative({
    profiles: [primary, fallback('backup')],
    routing: { ...routing, fallbackEnabled: true, fallbackProfileIds: ['backup'] }, prompt,
    requester: async ({ profile }) => { calls.push(profile.id); return { ok: true, text: '{}' }; },
  });
  assert.deepEqual(calls, ['primary']);
  assert.deepEqual(result, { ok: true, text: '{}', profileId: 'primary', attempts: ['primary'] });
});

test('fallback is disabled unless explicitly enabled', async () => {
  const calls = [];
  const result = await routeNarrative({
    profiles: [primary, fallback('backup')], routing: { ...routing, fallbackProfileIds: ['backup'] }, prompt,
    requester: async ({ profile }) => { calls.push(profile.id); return { ok: false, error: 'timeout' }; },
  });
  assert.deepEqual(calls, ['primary']);
  assert.equal(result.error, 'timeout');
});

test('temporary failures use fallbacks in explicit order', async () => {
  const calls = [];
  const result = await routeNarrative({
    profiles: [primary, fallback('backup-a'), fallback('backup-b')],
    routing: { ...routing, fallbackEnabled: true, fallbackProfileIds: ['backup-b', 'backup-a'] }, prompt,
    requester: async ({ profile }) => {
      calls.push(profile.id);
      return profile.id === 'backup-a' ? { ok: true, text: '{"ok":true}' } : { ok: false, error: 'rate_limited' };
    },
  });
  assert.deepEqual(calls, ['primary', 'backup-b', 'backup-a']);
  assert.equal(result.profileId, 'backup-a');
});

test('authentication, model and request failures never trigger fallback', async () => {
  for (const error of ['authentication_failed', 'model_not_found', 'request_rejected', 'invalid_response']) {
    const calls = [];
    const result = await routeNarrative({
      profiles: [primary, fallback('backup')],
      routing: { ...routing, fallbackEnabled: true, fallbackProfileIds: ['backup'] }, prompt,
      requester: async ({ profile }) => { calls.push(profile.id); return { ok: false, error }; },
    });
    assert.deepEqual(calls, ['primary']);
    assert.equal(result.error, error);
  }
});

test('attempt count never exceeds the configured maximum of three', async () => {
  const calls = [];
  const profiles = [primary, fallback('a'), fallback('b'), fallback('c')];
  const result = await routeNarrative({
    profiles,
    routing: { ...routing, fallbackEnabled: true, fallbackProfileIds: ['a', 'b', 'c'], maximumAttempts: 2 },
    prompt,
    requester: async ({ profile }) => { calls.push(profile.id); return { ok: false, error: 'upstream_unavailable' }; },
  });
  assert.deepEqual(calls, ['primary', 'a']);
  assert.deepEqual(result.attempts, ['primary', 'a']);
});
