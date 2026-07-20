import assert from 'node:assert/strict';
import test from 'node:test';

import { guardGroundedOutput } from '../src/llm/grounding-guard.mjs';

function assistantPrompt(templateAnswer, placeSummaries = []) {
  return {
    system: 'bounded assistant',
    user: JSON.stringify({
      questionType: 'nearby',
      templateAnswer,
      placeSummaries,
      tone: 'balanced',
    }),
  };
}

test('accepts a natural rewrite that keeps the same facts', () => {
  const result = guardGroundedOutput({
    prompt: assistantPrompt('当前窗口是18:20—18:45，先看时间再决定是否出发。'),
    text: JSON.stringify({ answer: '窗口仍是18:20—18:45，先确认时间再决定是否出发。' }),
  });
  assert.equal(result.ok, true);
});

test('rejects a new time, probability and action claim', () => {
  const newTime = guardGroundedOutput({
    prompt: assistantPrompt('当前窗口是18:20—18:45，先看时间再决定是否出发。'),
    text: JSON.stringify({ answer: '19:30出发最合适。' }),
  });
  assert.equal(newTime.ok, false);
  assert.equal(newTime.reason, 'unsupported_number');

  const probability = guardGroundedOutput({
    prompt: assistantPrompt('当前条件仍需观察。'),
    text: JSON.stringify({ answer: '成功率有80%。' }),
  });
  assert.equal(probability.ok, false);

  const action = guardGroundedOutput({
    prompt: assistantPrompt('当前条件仍需观察。'),
    text: JSON.stringify({ answer: '建议立即前往。' }),
  });
  assert.equal(action.ok, false);
  assert.equal(action.reason, 'unsupported_action');
});

test('rejects an ungrounded place or equipment item', () => {
  const place = guardGroundedOutput({
    prompt: assistantPrompt('当前附近可以先看西湖。', [{ name: '西湖' }]),
    text: JSON.stringify({ answer: '北山街是最佳选择。' }),
  });
  assert.equal(place.ok, false);
  assert.equal(place.reason, 'unsupported_place');

  const equipment = guardGroundedOutput({
    prompt: assistantPrompt('当前没有额外器材要求。'),
    text: JSON.stringify({ answer: '最好带无人机。' }),
  });
  assert.equal(equipment.ok, false);
  assert.equal(equipment.reason, 'unsupported_equipment');
});

test('narrative labels remain tied to allowed creative ids', () => {
  const prompt = {
    system: 'bounded narrative',
    user: JSON.stringify({
      templateSummary: '云层正在打开，继续观察。',
      allowedCreativeEventIds: ['event.one'],
    }),
  };
  const accepted = guardGroundedOutput({
    prompt,
    text: JSON.stringify({ summary: '云层正在打开，可以继续观察。', noteLabels: { 'event.one': '云开' } }),
  });
  assert.equal(accepted.ok, true);

  const rejected = guardGroundedOutput({
    prompt,
    text: JSON.stringify({ summary: '云层正在打开。', noteLabels: { 'event.two': '立刻出发' } }),
  });
  assert.equal(rejected.ok, false);
});
