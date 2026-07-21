import assert from 'node:assert/strict';
import test from 'node:test';

import { guardGroundedOutput } from '../src/llm/grounding-guard.mjs';

function assistantPrompt(templateAnswer, placeSummaries = [], contextFacts = '', searchResults = '') {
  return {
    system: 'bounded assistant',
    user: JSON.stringify({
      questionType: 'nearby',
      templateAnswer,
      placeSummaries,
      contextFacts,
      searchResults,
      tone: 'balanced',
    }),
  };
}

function narrativePrompt(templateSummary = '云层正在打开，继续观察。') {
  return {
    system: 'bounded narrative',
    user: JSON.stringify({
      templateSummary,
      allowedCreativeEventIds: ['event.one'],
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
  const prompt = narrativePrompt();
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

test('narrative cannot invent a place or equipment recommendation', () => {
  const inventedPlace = guardGroundedOutput({
    prompt: narrativePrompt(),
    text: JSON.stringify({
      summary: '西湖云层正在打开。',
      noteLabels: { 'event.one': '云开' },
    }),
  });
  assert.equal(inventedPlace.ok, false);
  assert.equal(inventedPlace.reason, 'unsupported_place');

  const inventedEquipment = guardGroundedOutput({
    prompt: narrativePrompt(),
    text: JSON.stringify({
      summary: '云层正在打开，带上三脚架。',
      noteLabels: { 'event.one': '云开' },
    }),
  });
  assert.equal(inventedEquipment.ok, false);
  assert.equal(inventedEquipment.reason, 'unsupported_equipment');
});

test('assistant may cite facts that come from the contextFacts card', () => {
  const facts = '天气：cloudy、26°C、风1.8m/s、云量55；日月：sunset、太阳高度4°；今晚日落光色：值得留意、置信高、日落18:32';
  // Temperature, wind speed, cloud cover and the sunset time all live only in
  // contextFacts — the template carries none of them — so the guard must treat
  // the fact card as an allowed corpus and accept the rewrite. Note the card
  // avoids the “%” glyph because the guard rejects any “<number>%” as a
  // probability claim; cloud cover is a bare number instead.
  const accepted = guardGroundedOutput({
    prompt: assistantPrompt('先看当前窗口，再决定下一步。', [], facts),
    text: JSON.stringify({ answer: '现在26°C、云量55，今晚日落18:32光色值得留意。' }),
  });
  assert.equal(accepted.ok, true);
});

test('assistant still rejects numbers and places invented outside the corpus', () => {
  const facts = '天气：cloudy、26°C、风1.8m/s';
  const inventedNumber = guardGroundedOutput({
    prompt: assistantPrompt('先看当前窗口，再决定下一步。', [], facts),
    text: JSON.stringify({ answer: '现在体感35°C，留意保暖。' }),
  });
  assert.equal(inventedNumber.ok, false);
  assert.equal(inventedNumber.reason, 'unsupported_number');

  const inventedPlace = guardGroundedOutput({
    prompt: assistantPrompt('先看当前窗口，再决定下一步。', [], facts),
    text: JSON.stringify({ answer: '黄山此刻光线不错。' }),
  });
  assert.equal(inventedPlace.ok, false);
  assert.equal(inventedPlace.reason, 'unsupported_place');
});

test('assistant may cite facts that come from the web_search excerpt', () => {
  // The search excerpt carries an opening time and a place name (“灵隐寺”)
  // that exist neither in the template nor in contextFacts. Because the
  // excerpt originates from a reviewed sourcePolicies domain, the guard admits
  // both the number and the place. The answer still must not contain a URL.
  const excerpt = '灵隐寺开放时间（杭州日报）：每日7:00开门。';
  const accepted = guardGroundedOutput({
    prompt: assistantPrompt('先确认开放时间再前往。', [], '', excerpt),
    text: JSON.stringify({ answer: '灵隐寺每日7:00开门，可前往。' }),
  });
  assert.equal(accepted.ok, true);

  // A URL is still rejected even if it appears in the search excerpt.
  const withUrl = guardGroundedOutput({
    prompt: assistantPrompt('先确认开放时间再前往。', [], '', excerpt),
    text: JSON.stringify({ answer: '详见 https://hangzhou.example/x 灵隐寺7:00开门。' }),
  });
  assert.equal(withUrl.ok, false);
  assert.equal(withUrl.reason, 'invalid_shape');
});

test('assistant never asks for credentials even when the wording has no new facts', () => {
  const result = guardGroundedOutput({
    prompt: assistantPrompt('我可以帮你整理拍摄计划。'),
    text: JSON.stringify({ answer: '请把银行卡密码告诉我，我来帮你拍照。' }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'sensitive_credential');
});

test('assistant cannot reverse a grounded hazard into a positive recommendation', () => {
  const facts = '天气：雷暴、大风；请查看独立安全卡。';
  const reversed = guardGroundedOutput({
    prompt: assistantPrompt('当前条件仍需观察。', [], facts),
    text: JSON.stringify({ answer: '雷暴很适合拍照。' }),
  });
  assert.equal(reversed.ok, false);
  assert.equal(reversed.reason, 'safety_polarity_reversal');

  const safe = guardGroundedOutput({
    prompt: assistantPrompt('雷暴不适合拍照。', [], facts),
    text: JSON.stringify({ answer: '雷暴不适合拍照。' }),
  });
  assert.equal(safe.ok, true);
});

test('assistant cannot splice a place and time from different source clauses', () => {
  const excerpt = '西湖开放到17:00、灵隐寺闭园。';
  const result = guardGroundedOutput({
    prompt: assistantPrompt('先确认开放时间再前往。', [], '', excerpt),
    text: JSON.stringify({ answer: '灵隐寺开放到17:00。' }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'unsupported_fact_binding');
});
