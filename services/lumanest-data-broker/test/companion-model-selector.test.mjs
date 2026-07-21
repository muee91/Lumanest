import assert from 'node:assert/strict';
import test from 'node:test';

import {
  creativeSelectionPrompt,
  parseCreativeSelection,
  selectCreativeWithModel,
} from '../src/companion/model-selector.mjs';

const candidates = [
  { id: 'creative.a', label: '前景', guide: '寻找前景', sceneAffinity: ['urban'], techniqueTags: ['foreground'] },
  { id: 'creative.b', label: '重复', guide: '寻找重复', sceneAffinity: ['urban'], techniqueTags: ['repetition'] },
  { id: 'creative.c', label: '留白', guide: '保留留白', sceneAffinity: ['urban'], techniqueTags: ['minimalism'] },
  { id: 'creative.d', label: '侧光', guide: '寻找侧光', sceneAffinity: ['urban'], techniqueTags: ['light'] },
];

const snapshot = {
  contextId: 'ctx_1234567890abcdef12345678',
  environment: {
    scene: 'city',
    sunMoon: { dayPhase: 'day' },
    weather: { type: 'cloudy' },
    route: { active: false },
  },
  facts: { events: [] },
};

test('selection prompt exposes bounded context and candidate ids without coordinates', () => {
  const prompt = creativeSelectionPrompt({ snapshot, candidates, maximum: 4 });
  const user = JSON.parse(prompt.user);

  assert.equal(user.context.scene, 'city');
  assert.equal(user.maximum, 4);
  assert.deepEqual(user.candidates.map((item) => item.id), candidates.map((item) => item.id));
  assert.equal(prompt.user.includes('latitude'), false);
  assert.equal(prompt.user.includes('longitude'), false);
});

test('selection parser accepts only unique ids from the candidate set', () => {
  assert.deepEqual(
    parseCreativeSelection(
      JSON.stringify({ selectedIds: ['creative.c', 'creative.a', 'creative.d'] }),
      candidates,
      4,
    ),
    ['creative.c', 'creative.a', 'creative.d'],
  );
  assert.deepEqual(
    parseCreativeSelection(JSON.stringify({ selectedIds: ['creative.a', 'invented', 'creative.c'] }), candidates, 4),
    [],
  );
  assert.deepEqual(
    parseCreativeSelection(JSON.stringify({ selectedIds: ['creative.a', 'creative.a', 'creative.c'] }), candidates, 4),
    [],
  );
});

test('model selector degrades to no inspiration when AI is unavailable', async () => {
  let routerCalls = 0;
  const result = await selectCreativeWithModel({
    snapshot,
    candidates,
    maximum: 4,
    profiles: [],
    routing: { primaryProfileId: null },
    aiEnabled: false,
    router: async () => { routerCalls += 1; },
  });

  assert.deepEqual(result, []);
  assert.equal(routerCalls, 0);
});

test('model selector returns the strict model-ranked ids', async () => {
  const result = await selectCreativeWithModel({
    snapshot,
    candidates,
    maximum: 4,
    profiles: [{ id: 'primary', enabled: true, model: 'model-a' }],
    routing: {
      primaryProfileId: 'primary',
      fallbackEnabled: false,
      fallbackProfileIds: [],
      maximumAttempts: 1,
    },
    aiEnabled: true,
    router: async () => ({
      ok: true,
      text: JSON.stringify({ selectedIds: ['creative.b', 'creative.d', 'creative.a'] }),
    }),
  });

  assert.deepEqual(result, ['creative.b', 'creative.d', 'creative.a']);
});

test('model selector tries an allowed fallback after an invalid primary response', async () => {
  const calls = [];
  const result = await selectCreativeWithModel({
    snapshot,
    candidates,
    maximum: 4,
    profiles: [
      { id: 'primary', enabled: true, model: 'model-a', allowFallback: false },
      { id: 'fallback', enabled: true, model: 'model-b', allowFallback: true },
    ],
    routing: {
      primaryProfileId: 'primary',
      fallbackEnabled: true,
      fallbackProfileIds: ['fallback'],
      maximumAttempts: 2,
    },
    aiEnabled: true,
    router: async ({ routing }) => {
      calls.push(routing.primaryProfileId);
      return routing.primaryProfileId === 'primary'
        ? { ok: false, error: 'invalid_response' }
        : {
            ok: true,
            text: JSON.stringify({
              selectedIds: ['creative.d', 'creative.c', 'creative.a'],
            }),
          };
    },
  });

  assert.deepEqual(calls, ['primary', 'fallback']);
  assert.deepEqual(result, ['creative.d', 'creative.c', 'creative.a']);
});
